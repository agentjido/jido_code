defmodule JidoCode.Conversations.Coordinator do
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  @moduledoc """
  Coordinator process for one active conversation.

  Owns command admission, append-only event sequencing, turn lifecycle, and
  product-readable snapshots for delivery and reconnect recovery.
  """

  use GenServer

  alias JidoCode.Conversations.{
    ChildWork,
    ChildWorker,
    Command,
    Conversation,
    Event,
    Persistence,
    PubSub,
    Snapshot,
    Turn
  }

  @type state :: %{
          conversation: Conversation.t(),
          status: atom(),
          admission_paused: boolean(),
          child_execution_paused: boolean(),
          active_turn_id: String.t() | nil,
          work_queue: [String.t()],
          turns: %{String.t() => Turn.t()},
          turn_order: [String.t()],
          control_history: [map()],
          child_works: %{String.t() => ChildWork.t()},
          child_work_order: [String.t()],
          child_worker_pids: %{String.t() => pid()},
          event_sequence: non_neg_integer(),
          events: [Event.t()]
        }

  def start_link(%Conversation{} = conversation) do
    GenServer.start_link(__MODULE__, conversation, name: via_tuple(conversation.id))
  end

  @spec via_tuple(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(conversation_id), do: {:via, Registry, {JidoCode.Conversations.Registry, conversation_id}}

  @spec admit_command(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def admit_command(conversation_id, command, actor) do
    GenServer.call(via_tuple(conversation_id), {:admit_command, command, actor})
  end

  @spec transition_turn(String.t(), String.t(), atom(), map()) :: {:ok, map()} | {:error, term()}
  def transition_turn(conversation_id, turn_id, next_state, actor \\ %{}) do
    GenServer.call(via_tuple(conversation_id), {:transition_turn, turn_id, next_state, actor})
  end

  @spec cancel_child_work(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def cancel_child_work(conversation_id, child_work_id, actor \\ %{}) do
    GenServer.call(via_tuple(conversation_id), {:cancel_child_work, child_work_id, actor})
  end

  @spec settle_child_work(String.t(), String.t(), ChildWork.settlement(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def settle_child_work(conversation_id, child_work_id, outcome, attrs \\ %{}, actor \\ %{}) do
    GenServer.call(via_tuple(conversation_id), {:settle_child_work, child_work_id, outcome, attrs, actor})
  end

  @spec snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(conversation_id) do
    GenServer.call(via_tuple(conversation_id), :snapshot)
  end

  @spec events_since(String.t(), non_neg_integer()) :: {:ok, [map()]} | {:error, term()}
  def events_since(conversation_id, after_sequence) do
    GenServer.call(via_tuple(conversation_id), {:events_since, after_sequence})
  end

  @impl true
  def init(%Conversation{} = conversation) do
    state =
      case Persistence.restore_state(conversation) do
        {:ok, restored_state} when is_map(restored_state) -> restored_state
        _other -> fresh_state(conversation)
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:admit_command, command, actor}, _from, state) do
    with {:ok, normalized_command} <- Command.normalize(command, actor),
         {:ok, next_state} <- admit_normalized_command(state, normalized_command),
         :ok <- Persistence.persist_transition(state, next_state),
         :ok <- broadcast_new_events(state, next_state) do
      {:reply, {:ok, Snapshot.from_state(next_state)}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:transition_turn, turn_id, next_state, actor}, _from, state) do
    case Map.fetch(state.turns, turn_id) do
      {:ok, %Turn{} = turn} ->
        with {:ok, updated_turn} <- Turn.transition(turn, next_state),
             {:ok, next_state_map} <- apply_turn_transition(state, updated_turn, actor),
             :ok <- Persistence.persist_transition(state, next_state_map),
             :ok <- broadcast_new_events(state, next_state_map) do
          {:reply, {:ok, Snapshot.from_state(next_state_map)}, next_state_map}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      :error ->
        {:reply, {:error, :turn_not_found}, state}
    end
  end

  def handle_call({:cancel_child_work, child_work_id, actor}, _from, state) do
    with {:ok, pid} <- fetch_child_worker_pid(state, child_work_id),
         child_work <- Map.fetch!(state.child_works, child_work_id),
         next_state <- append_child_work_cancel_requested_event(state, child_work, actor, %{}),
         {:ok, updated_child_work} <- ChildWorker.request_cancel(pid),
         {:ok, final_state} <- apply_child_work_update(next_state, updated_child_work, actor),
         :ok <- Persistence.persist_transition(state, final_state),
         :ok <- broadcast_new_events(state, final_state) do
      {:reply, {:ok, Snapshot.from_state(final_state)}, final_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:settle_child_work, child_work_id, outcome, attrs, actor}, _from, state) do
    with {:ok, updated_child_work} <- settle_child_work_runtime(state, child_work_id, outcome, attrs),
         {:ok, next_state} <- apply_child_work_update(state, updated_child_work, actor, attrs),
         :ok <- Persistence.persist_transition(state, next_state),
         :ok <- broadcast_new_events(state, next_state) do
      {:reply, {:ok, Snapshot.from_state(next_state)}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:events_since, after_sequence}, _from, state)
      when is_integer(after_sequence) and after_sequence >= 0 do
    {:reply, {:ok, events_after(state, after_sequence)}, state}
  end

  def handle_call({:events_since, _after_sequence}, _from, state) do
    {:reply, {:error, :invalid_sequence}, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, Snapshot.from_state(state)}, state}
  end

  defp admit_normalized_command(state, %{class: :work} = normalized_command) do
    turn = Turn.new(state.conversation.id, normalized_command)

    state
    |> append_command_message_event(normalized_command)
    |> update_in([:turn_order], &(&1 ++ [turn.id]))
    |> update_in([:work_queue], &(&1 ++ [turn.id]))
    |> store_turn(turn, actor: normalized_command.actor, message_id: normalized_command.id)
    |> maybe_append_turn_intent_event(turn, normalized_command)
    |> maybe_activate_next_turn()
  end

  defp admit_normalized_command(state, %{class: :control} = normalized_command) do
    with {:ok, next_state} <-
           state
           |> append_command_message_event(normalized_command)
           |> update_in([:control_history], &(&1 ++ [control_entry(normalized_command)]))
           |> apply_control_command(normalized_command)
           |> maybe_activate_next_turn() do
      {:ok, next_state}
    end
  end

  defp apply_control_command(state, %{type: :session_pause} = normalized_command) do
    next_state = %{
      state
      | status: :paused,
        admission_paused: true,
        child_execution_paused: false,
        conversation: %{state.conversation | status: :paused}
    }

    {:ok, append_status_event(next_state, normalized_command)}
  end

  defp apply_control_command(state, %{type: :session_resume} = normalized_command) do
    next_state = %{
      state
      | status: :active,
        admission_paused: false,
        child_execution_paused: false,
        conversation: %{state.conversation | status: :active}
    }

    {:ok, append_status_event(next_state, normalized_command)}
  end

  defp apply_control_command(state, %{type: :turn_stop} = normalized_command) do
    stop_turn(state, normalized_command.payload, normalized_command.actor, normalized_command.id)
  end

  defp apply_control_command(state, %{type: :tool_cancel} = normalized_command) do
    cancel_tool(state, normalized_command.payload, normalized_command.actor, normalized_command.id)
  end

  defp apply_control_command(state, %{type: :turn_steer} = normalized_command) do
    steer_turn(state, normalized_command)
  end

  defp apply_control_command(state, _normalized_command), do: {:ok, state}

  defp maybe_activate_next_turn({:ok, state}), do: maybe_activate_next_turn(state)

  defp maybe_activate_next_turn(%{status: :paused} = state), do: {:ok, state}
  defp maybe_activate_next_turn(%{admission_paused: true} = state), do: {:ok, state}
  defp maybe_activate_next_turn(%{active_turn_id: active_turn_id} = state) when not is_nil(active_turn_id), do: {:ok, state}

  defp maybe_activate_next_turn(%{work_queue: [next_turn_id | remaining_turn_ids]} = state) do
    %Turn{} = next_turn = Map.fetch!(state.turns, next_turn_id)

    with {:ok, running_turn} <- Turn.transition(next_turn, :running),
         child_work <- ChildWork.new(state.conversation, running_turn),
         {:ok, pid} <- ChildWorker.start(child_work),
         {:ok, running_child_work} <- ChildWorker.snapshot(pid) do
      running_turn = %{running_turn | child_work_id: running_child_work.id}

      {:ok,
       state
       |> Map.put(:active_turn_id, next_turn_id)
       |> Map.put(:work_queue, remaining_turn_ids)
       |> update_in([:child_work_order], &(&1 ++ [running_child_work.id]))
       |> put_in([:child_worker_pids, running_child_work.id], pid)
       |> store_turn(running_turn, actor: running_turn.actor, message_id: running_turn.command_id)
       |> store_child_work(running_child_work, actor: running_child_work.actor, message_id: running_turn.command_id)}
    end
  end

  defp maybe_activate_next_turn(state), do: {:ok, state}

  defp apply_turn_transition(state, %Turn{} = updated_turn, actor \\ %{}, attrs \\ %{}) do
    next_state =
      state
      |> store_turn(updated_turn, actor: actor, payload: attrs, message_id: updated_turn.command_id)
      |> sync_child_work_with_turn(updated_turn, actor)

    if Turn.terminal_state?(updated_turn.state) and next_state.active_turn_id == updated_turn.id do
      next_state
      |> Map.put(:active_turn_id, nil)
      |> maybe_activate_next_turn()
    else
      {:ok, next_state}
    end
  end

  defp apply_child_work_update(state, %ChildWork{} = updated_child_work, actor \\ %{}, attrs \\ %{}) do
    next_state =
      state
      |> store_child_work(updated_child_work, actor: actor, payload: attrs)
      |> maybe_drop_child_worker(updated_child_work)

    if ChildWork.terminal_state?(updated_child_work.state) do
      turn = Map.fetch!(next_state.turns, updated_child_work.turn_id)

      with {:ok, settled_turn} <- Turn.transition(turn, settled_turn_state(turn, updated_child_work.state)) do
        apply_turn_transition(next_state, settled_turn, actor, attrs)
      end
    else
      {:ok, next_state}
    end
  end

  defp settle_child_work_runtime(state, child_work_id, outcome, attrs) do
    case Map.fetch(state.child_worker_pids, child_work_id) do
      {:ok, pid} ->
        ChildWorker.settle(pid, outcome, attrs)

      :error ->
        state.child_works
        |> Map.fetch(child_work_id)
        |> case do
          {:ok, %ChildWork{} = child_work} -> ChildWork.settle(child_work, outcome, attrs)
          :error -> {:error, :child_work_not_found}
        end
    end
  end

  defp fetch_child_worker_pid(state, child_work_id) do
    case Map.fetch(state.child_worker_pids, child_work_id) do
      {:ok, pid} -> {:ok, pid}
      :error -> {:error, :child_work_already_settled}
    end
  end

  defp maybe_drop_child_worker(state, %ChildWork{} = child_work) do
    if ChildWork.terminal_state?(child_work.state) do
      update_in(state, [:child_worker_pids], &Map.delete(&1, child_work.id))
    else
      state
    end
  end

  defp child_work_terminal_state(:completed), do: :completed
  defp child_work_terminal_state(:cancelled), do: :cancelled
  defp child_work_terminal_state(:cancel_failed), do: :failed
  defp child_work_terminal_state(:failed), do: :failed

  defp settled_turn_state(%Turn{state: :superseding}, :cancelled), do: :superseded
  defp settled_turn_state(_turn, child_work_state), do: child_work_terminal_state(child_work_state)

  defp sync_child_work_with_turn(state, %Turn{state: turn_state, child_work_id: child_work_id}, actor)
       when turn_state in [:completed, :cancelled, :failed] and is_binary(child_work_id) do
    case Map.fetch(state.child_worker_pids, child_work_id) do
      {:ok, pid} ->
        child_work = Map.fetch!(state.child_works, child_work_id)
        {:ok, settled_child_work} = ChildWork.settle(child_work, turn_state)
        _ = DynamicSupervisor.terminate_child(JidoCode.Conversations.ChildSupervisor, pid)

        state
        |> store_child_work(settled_child_work, actor: actor)
        |> update_in([:child_worker_pids], &Map.delete(&1, child_work_id))

      :error ->
        state
    end
  end

  defp sync_child_work_with_turn(state, _updated_turn, _actor), do: state

  defp control_entry(command) do
    %{
      id: command.id,
      type: command.raw_type,
      class: command.class,
      admitted_at: command.admitted_at,
      actor: command.actor,
      payload: command.payload
    }
  end

  defp stop_turn(state, payload, actor, message_id) do
    case target_turn(state, payload) do
      {:ok, %Turn{} = turn} ->
        request_turn_cancellation(state, turn, actor, payload, message_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cancel_tool(state, payload, actor, message_id \\ nil) do
    with {:ok, child_work_id} <- target_child_work_id(state, payload),
         {:ok, pid} <- fetch_child_worker_pid(state, child_work_id),
         {:ok, next_state} <- mark_parent_turn_cancelling(state, child_work_id, actor, payload, message_id),
         child_work <- Map.fetch!(next_state.child_works, child_work_id),
         final_state <- append_child_work_cancel_requested_event(next_state, child_work, actor, payload, message_id),
         {:ok, updated_child_work} <- ChildWorker.request_cancel(pid) do
      apply_child_work_update(final_state, updated_child_work, actor, payload)
    end
  end

  defp steer_turn(state, normalized_command) do
    with {:ok, target_turn} <- target_turn(state, normalized_command.payload),
         {:ok, state_after_target} <-
           mark_turn_superseding(
             state,
             target_turn,
             normalized_command.actor,
             normalized_command.payload,
             normalized_command.id
           ),
         {:ok, replacement_turn} <- build_replacement_turn(state_after_target, normalized_command, target_turn.id),
         {:ok, queued_state} <- enqueue_priority_turn(state_after_target, replacement_turn) do
      update_superseded_reference(queued_state, target_turn.id, replacement_turn.id)
    end
  end

  defp request_turn_cancellation(state, %Turn{state: :queued, id: turn_id} = turn, actor, payload, message_id) do
    with {:ok, cancelled_turn} <- Turn.transition(turn, :cancelled) do
      state
      |> update_in([:work_queue], &Enum.reject(&1, fn queued_turn_id -> queued_turn_id == turn_id end))
      |> store_turn(cancelled_turn, actor: actor, payload: payload, message_id: message_id)
      |> then(&{:ok, &1})
    end
  end

  defp request_turn_cancellation(state, %Turn{} = turn, actor, payload, message_id) do
    with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling) do
      next_state = store_turn(state, cancelling_turn, actor: actor, payload: payload, message_id: message_id)

      case turn.child_work_id do
        child_work_id when is_binary(child_work_id) ->
          cancel_tool(next_state, %{"child_work_id" => child_work_id} |> Map.merge(payload), actor, message_id)

        _ ->
          with {:ok, cancelled_turn} <- Turn.transition(cancelling_turn, :cancelled) do
            apply_turn_transition(next_state, cancelled_turn, actor, payload)
          end
      end
    end
  end

  defp mark_parent_turn_cancelling(state, child_work_id, actor, payload, message_id) do
    child_work = Map.fetch!(state.child_works, child_work_id)
    turn = Map.fetch!(state.turns, child_work.turn_id)

    case turn.state do
      :running ->
        with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling) do
          {:ok, store_turn(state, cancelling_turn, actor: actor, payload: payload, message_id: message_id)}
        end

      :awaiting_input ->
        with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling) do
          {:ok, store_turn(state, cancelling_turn, actor: actor, payload: payload, message_id: message_id)}
        end

      _ ->
        {:ok, state}
    end
  end

  defp mark_turn_superseding(state, %Turn{state: :queued, id: turn_id} = turn, actor, payload, message_id) do
    with {:ok, superseded_turn} <- Turn.transition(turn, :superseded) do
      state
      |> update_in([:work_queue], &Enum.reject(&1, fn queued_turn_id -> queued_turn_id == turn_id end))
      |> store_turn(superseded_turn, actor: actor, payload: payload, message_id: message_id)
      |> then(&{:ok, &1})
    end
  end

  defp mark_turn_superseding(state, %Turn{} = turn, actor, payload, message_id) do
    with {:ok, superseding_turn} <- Turn.transition(turn, :superseding) do
      next_state = store_turn(state, superseding_turn, actor: actor, payload: payload, message_id: message_id)

      case turn.child_work_id do
        child_work_id when is_binary(child_work_id) ->
          with {:ok, pid} <- fetch_child_worker_pid(next_state, child_work_id),
               child_work <- Map.fetch!(next_state.child_works, child_work_id),
               requested_state <- append_child_work_cancel_requested_event(next_state, child_work, actor, payload, message_id),
               {:ok, updated_child_work} <- ChildWorker.request_cancel(pid) do
            apply_child_work_update(requested_state, updated_child_work, actor, payload)
          end

        _ ->
          with {:ok, superseded_turn} <- Turn.transition(superseding_turn, :superseded) do
            apply_turn_transition(next_state, superseded_turn, actor, payload)
          end
      end
    end
  end

  defp build_replacement_turn(state, normalized_command, supersedes_turn_id) do
    {:ok, Turn.new(state.conversation.id, normalized_command, %{supersedes_turn_id: supersedes_turn_id})}
  end

  defp enqueue_priority_turn(state, %Turn{} = turn) do
    {:ok,
     state
     |> update_in([:turn_order], &(&1 ++ [turn.id]))
     |> update_in([:work_queue], &[turn.id | &1])
     |> store_turn(turn, actor: turn.actor, message_id: turn.command_id)
     |> maybe_append_turn_intent_event(turn, %{id: turn.command_id})}
  end

  defp update_superseded_reference(state, target_turn_id, replacement_turn_id) do
    turn = Map.fetch!(state.turns, target_turn_id)
    updated_turn = %{turn | superseded_by_turn_id: replacement_turn_id}
    put_turn(state, updated_turn)
  end

  defp put_turn(state, %Turn{} = turn) do
    {:ok, put_in(state, [:turns, turn.id], turn)}
  end

  defp target_turn(state, payload) do
    case target_turn_id(state, payload) do
      {:ok, turn_id} ->
        case Map.fetch(state.turns, turn_id) do
          {:ok, %Turn{} = turn} -> {:ok, turn}
          :error -> {:error, :turn_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp target_turn_id(state, payload) do
    payload_turn_id = Map.get(payload, "turn_id")

    cond do
      is_binary(payload_turn_id) ->
        {:ok, payload_turn_id}

      is_binary(state.active_turn_id) ->
        {:ok, state.active_turn_id}

      state.work_queue != [] ->
        {:ok, hd(state.work_queue)}

      true ->
        {:error, :turn_not_found}
    end
  end

  defp target_child_work_id(state, payload) do
    payload_child_work_id = Map.get(payload, "child_work_id")

    cond do
      is_binary(payload_child_work_id) ->
        {:ok, payload_child_work_id}

      is_binary(state.active_turn_id) ->
        case Map.get(state.turns, state.active_turn_id) do
          %Turn{child_work_id: child_work_id} when is_binary(child_work_id) -> {:ok, child_work_id}
          _ -> {:error, :child_work_not_found}
        end

      true ->
        {:error, :child_work_not_found}
    end
  end

  defp events_after(state, after_sequence) do
    state.events
    |> Enum.map(&Event.summary/1)
    |> Enum.filter(&(&1.sequence > after_sequence))
  end

  defp append_command_message_event(state, normalized_command) do
    append_event(state, "conversation.message_added", %{
      actor: normalized_command.actor,
      message_id: normalized_command.id,
      correlation: %{
        "command_type" => normalized_command.raw_type,
        "command_class" => Atom.to_string(normalized_command.class)
      },
      payload: %{
        "command_type" => normalized_command.raw_type,
        "command_class" => Atom.to_string(normalized_command.class),
        "payload" => normalized_command.payload
      }
    })
  end

  defp maybe_append_turn_intent_event(state, %Turn{} = turn, _command) do
    intent_text =
      Map.get(turn.payload, "instruction") ||
        Map.get(turn.payload, "intent") ||
        Map.get(turn.payload, "reason") ||
        Map.get(turn.payload, "summary")

    case optional_string(intent_text) do
      nil ->
        state

      text ->
        append_event(state, "turn.intent_announced", %{
          actor: turn.actor,
          message_id: turn.command_id,
          turn_id: turn.id,
          correlation: turn_correlation(turn),
          payload: %{
            "text" => text,
            "command_type" => turn.command_type
          }
        })
    end
  end

  defp append_child_work_cancel_requested_event(state, %ChildWork{} = child_work, actor, payload, message_id \\ nil) do
    append_event(state, "tool.cancel_requested", %{
      actor: actor,
      message_id: message_id,
      turn_id: child_work.turn_id,
      child_work_id: child_work.id,
      tool_call_id: child_work.tool_call_id,
      correlation: child_work_correlation(child_work),
      payload:
        %{
          "kind" => child_work.kind,
          "request" => payload
        }
        |> maybe_put("result", child_work.result)
        |> maybe_put("error", child_work.error)
    })
  end

  defp append_status_event(state, normalized_command) do
    append_event(state, "conversation.status_changed", %{
      actor: normalized_command.actor,
      message_id: normalized_command.id,
      correlation: %{
        "command_type" => normalized_command.raw_type
      },
      payload: %{
        "status" => Atom.to_string(state.status),
        "admission_paused" => state.admission_paused,
        "child_execution_paused" => state.child_execution_paused
      }
    })
  end

  defp store_turn(state, %Turn{} = updated_turn, opts \\ []) do
    previous_turn = Map.get(state.turns, updated_turn.id)
    next_state = put_in(state, [:turns, updated_turn.id], updated_turn)
    maybe_append_turn_state_event(next_state, previous_turn, updated_turn, opts)
  end

  defp store_child_work(state, %ChildWork{} = updated_child_work, opts \\ []) do
    previous_child_work = Map.get(state.child_works, updated_child_work.id)
    next_state = put_in(state, [:child_works, updated_child_work.id], updated_child_work)
    maybe_append_child_work_state_event(next_state, previous_child_work, updated_child_work, opts)
  end

  defp maybe_append_turn_state_event(state, previous_turn, %Turn{} = updated_turn, opts) do
    case turn_event_name(previous_turn, updated_turn) do
      nil ->
        state

      event_name ->
        append_event(state, event_name, %{
          actor: Keyword.get(opts, :actor, updated_turn.actor),
          message_id: Keyword.get(opts, :message_id),
          turn_id: updated_turn.id,
          child_work_id: updated_turn.child_work_id,
          correlation: turn_correlation(updated_turn),
          payload:
            %{
              "state" => Atom.to_string(updated_turn.state),
              "command_type" => updated_turn.command_type,
              "payload" => updated_turn.payload
            }
            |> maybe_put("attrs", Keyword.get(opts, :payload))
        })
    end
  end

  defp maybe_append_child_work_state_event(state, previous_child_work, %ChildWork{} = updated_child_work, opts) do
    case child_work_event_name(previous_child_work, updated_child_work) do
      nil ->
        state

      event_name ->
        append_event(state, event_name, %{
          actor: Keyword.get(opts, :actor, updated_child_work.actor),
          turn_id: updated_child_work.turn_id,
          child_work_id: updated_child_work.id,
          tool_call_id: updated_child_work.tool_call_id,
          correlation: child_work_correlation(updated_child_work),
          payload:
            %{
              "state" => Atom.to_string(updated_child_work.state),
              "kind" => updated_child_work.kind
            }
            |> maybe_put("result", updated_child_work.result)
            |> maybe_put("error", updated_child_work.error)
            |> maybe_put("attrs", Keyword.get(opts, :payload))
        })
    end
  end

  defp append_event(state, name, attrs) do
    sequence = state.event_sequence + 1
    event = Event.new(state.conversation.id, sequence, name, attrs)

    %{
      state
      | event_sequence: sequence,
        events: state.events ++ [event]
    }
  end

  defp broadcast_new_events(previous_state, next_state) do
    next_state.events
    |> Enum.filter(&(&1.sequence > previous_state.event_sequence))
    |> Enum.each(fn event ->
      _ = PubSub.broadcast_conversation_event(next_state.conversation.id, Event.summary(event))
    end)

    :ok
  end

  defp fresh_state(%Conversation{} = conversation) do
    %{
      conversation: conversation,
      status: conversation.status,
      admission_paused: conversation.status == :paused,
      child_execution_paused: false,
      active_turn_id: nil,
      work_queue: [],
      turns: %{},
      turn_order: [],
      control_history: [],
      child_works: %{},
      child_work_order: [],
      child_worker_pids: %{},
      event_sequence: 0,
      events: []
    }
  end

  defp turn_event_name(nil, %Turn{state: :queued}), do: "turn.queued"
  defp turn_event_name(%Turn{state: previous_state}, %Turn{state: next_state}) when previous_state == next_state, do: nil
  defp turn_event_name(_previous_turn, %Turn{state: :running}), do: "turn.started"
  defp turn_event_name(_previous_turn, %Turn{state: :awaiting_input}), do: "turn.awaiting_input"
  defp turn_event_name(_previous_turn, %Turn{state: :cancelling}), do: "turn.cancelling"
  defp turn_event_name(_previous_turn, %Turn{state: :superseding}), do: "turn.superseding"
  defp turn_event_name(_previous_turn, %Turn{state: :completed}), do: "turn.completed"
  defp turn_event_name(_previous_turn, %Turn{state: :cancelled}), do: "turn.cancelled"
  defp turn_event_name(_previous_turn, %Turn{state: :superseded}), do: "turn.superseded"
  defp turn_event_name(_previous_turn, %Turn{state: :failed}), do: "turn.failed"
  defp turn_event_name(_previous_turn, _updated_turn), do: nil

  defp child_work_event_name(nil, %ChildWork{state: :running}), do: "tool.started"
  defp child_work_event_name(%ChildWork{state: previous_state}, %ChildWork{state: next_state}) when previous_state == next_state, do: nil
  defp child_work_event_name(_previous_child_work, %ChildWork{state: :running}), do: "tool.started"
  defp child_work_event_name(_previous_child_work, %ChildWork{state: :cancel_acknowledged}), do: "tool.cancel_acknowledged"
  defp child_work_event_name(_previous_child_work, %ChildWork{state: :completed}), do: "tool.completed"
  defp child_work_event_name(_previous_child_work, %ChildWork{state: :cancelled}), do: "tool.cancelled"
  defp child_work_event_name(_previous_child_work, %ChildWork{state: :cancel_failed}), do: "tool.cancel_failed"
  defp child_work_event_name(_previous_child_work, %ChildWork{state: :failed}), do: "tool.failed"
  defp child_work_event_name(_previous_child_work, _updated_child_work), do: nil

  defp turn_correlation(%Turn{} = turn) do
    %{}
    |> maybe_put("command_id", turn.command_id)
    |> maybe_put("supersedes_turn_id", turn.supersedes_turn_id)
    |> maybe_put("superseded_by_turn_id", turn.superseded_by_turn_id)
  end

  defp child_work_correlation(%ChildWork{} = child_work) do
    %{}
    |> maybe_put("turn_id", child_work.turn_id)
    |> maybe_put("kind", child_work.kind)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(_value), do: nil
end
