defmodule JidoCode.Conversations.Coordinator do
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  @moduledoc """
  Coordinator process for one active conversation.

  Owns command admission, baseline turn lifecycle, and product-readable snapshots.
  """

  use GenServer

  alias JidoCode.Conversations.{ChildWork, ChildWorker, Command, Conversation, Turn}

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
          child_worker_pids: %{String.t() => pid()}
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

  @spec transition_turn(String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def transition_turn(conversation_id, turn_id, next_state) do
    GenServer.call(via_tuple(conversation_id), {:transition_turn, turn_id, next_state})
  end

  @spec cancel_child_work(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_child_work(conversation_id, child_work_id) do
    GenServer.call(via_tuple(conversation_id), {:cancel_child_work, child_work_id})
  end

  @spec settle_child_work(String.t(), String.t(), ChildWork.settlement(), map()) :: {:ok, map()} | {:error, term()}
  def settle_child_work(conversation_id, child_work_id, outcome, attrs \\ %{}) do
    GenServer.call(via_tuple(conversation_id), {:settle_child_work, child_work_id, outcome, attrs})
  end

  @spec snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(conversation_id) do
    GenServer.call(via_tuple(conversation_id), :snapshot)
  end

  @impl true
  def init(%Conversation{} = conversation) do
    {:ok,
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
       child_worker_pids: %{}
     }}
  end

  @impl true
  def handle_call({:admit_command, command, actor}, _from, state) do
    with {:ok, normalized_command} <- Command.normalize(command, actor),
         {:ok, next_state} <- admit_normalized_command(state, normalized_command) do
      {:reply, {:ok, snapshot_from_state(next_state)}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:transition_turn, turn_id, next_state}, _from, state) do
    case Map.fetch(state.turns, turn_id) do
      {:ok, %Turn{} = turn} ->
        with {:ok, updated_turn} <- Turn.transition(turn, next_state),
             {:ok, next_state_map} <- apply_turn_transition(state, updated_turn) do
          {:reply, {:ok, snapshot_from_state(next_state_map)}, next_state_map}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      :error ->
        {:reply, {:error, :turn_not_found}, state}
    end
  end

  def handle_call({:cancel_child_work, child_work_id}, _from, state) do
    with {:ok, pid} <- fetch_child_worker_pid(state, child_work_id),
         {:ok, updated_child_work} <- ChildWorker.request_cancel(pid),
         {:ok, next_state} <- apply_child_work_update(state, updated_child_work) do
      {:reply, {:ok, snapshot_from_state(next_state)}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:settle_child_work, child_work_id, outcome, attrs}, _from, state) do
    with {:ok, pid} <- fetch_child_worker_pid(state, child_work_id),
         {:ok, updated_child_work} <- ChildWorker.settle(pid, outcome, attrs),
         {:ok, next_state} <- apply_child_work_update(state, updated_child_work) do
      {:reply, {:ok, snapshot_from_state(next_state)}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, snapshot_from_state(state)}, state}
  end

  defp admit_normalized_command(state, %{class: :work} = normalized_command) do
    turn = Turn.new(state.conversation.id, normalized_command)

    state
    |> put_in([:turns, turn.id], turn)
    |> update_in([:turn_order], &(&1 ++ [turn.id]))
    |> update_in([:work_queue], &(&1 ++ [turn.id]))
    |> maybe_activate_next_turn()
  end

  defp admit_normalized_command(state, %{class: :control} = normalized_command) do
    with {:ok, next_state} <-
           state
           |> update_in([:control_history], &(&1 ++ [control_entry(normalized_command)]))
           |> apply_control_command(normalized_command)
           |> maybe_activate_next_turn() do
      {:ok, next_state}
    end
  end

  defp apply_control_command(state, %{type: :session_pause}) do
    {:ok,
     %{
       state
       | status: :paused,
         admission_paused: true,
         child_execution_paused: false,
         conversation: %{state.conversation | status: :paused}
     }}
  end

  defp apply_control_command(state, %{type: :session_resume}) do
    {:ok,
     %{
       state
       | status: :active,
         admission_paused: false,
         child_execution_paused: false,
         conversation: %{state.conversation | status: :active}
     }}
  end

  defp apply_control_command(state, %{type: :turn_stop} = normalized_command) do
    stop_turn(state, normalized_command.payload)
  end

  defp apply_control_command(state, %{type: :tool_cancel} = normalized_command) do
    cancel_tool(state, normalized_command.payload)
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
       |> put_in([:turns, next_turn_id], running_turn)
       |> put_in([:child_works, running_child_work.id], running_child_work)
       |> update_in([:child_work_order], &(&1 ++ [running_child_work.id]))
       |> put_in([:child_worker_pids, running_child_work.id], pid)
       |> Map.put(:active_turn_id, next_turn_id)
       |> Map.put(:work_queue, remaining_turn_ids)}
    end
  end

  defp maybe_activate_next_turn(state), do: {:ok, state}

  defp apply_turn_transition(state, %Turn{} = updated_turn) do
    next_state =
      state
      |> put_in([:turns, updated_turn.id], updated_turn)
      |> sync_child_work_with_turn(updated_turn)

    if Turn.terminal_state?(updated_turn.state) and next_state.active_turn_id == updated_turn.id do
      next_state
      |> Map.put(:active_turn_id, nil)
      |> maybe_activate_next_turn()
    else
      {:ok, next_state}
    end
  end

  defp apply_child_work_update(state, %ChildWork{} = updated_child_work) do
    next_state =
      state
      |> put_in([:child_works, updated_child_work.id], updated_child_work)
      |> maybe_drop_child_worker(updated_child_work)

    if ChildWork.terminal_state?(updated_child_work.state) do
      turn = Map.fetch!(next_state.turns, updated_child_work.turn_id)

      with {:ok, settled_turn} <- Turn.transition(turn, settled_turn_state(turn, updated_child_work.state)) do
        apply_turn_transition(next_state, settled_turn)
      end
    else
      {:ok, next_state}
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

  defp sync_child_work_with_turn(state, %Turn{state: turn_state, child_work_id: child_work_id})
       when turn_state in [:completed, :cancelled, :failed] and is_binary(child_work_id) do
    case Map.fetch(state.child_worker_pids, child_work_id) do
      {:ok, pid} ->
        child_work = Map.fetch!(state.child_works, child_work_id)
        {:ok, settled_child_work} = ChildWork.settle(child_work, turn_state)
        _ = DynamicSupervisor.terminate_child(JidoCode.Conversations.ChildSupervisor, pid)

        state
        |> put_in([:child_works, child_work_id], settled_child_work)
        |> update_in([:child_worker_pids], &Map.delete(&1, child_work_id))

      :error ->
        state
    end
  end

  defp sync_child_work_with_turn(state, _updated_turn), do: state

  defp snapshot_from_state(state) do
    active_child_work_id =
      state.active_turn_id
      |> then(&state.turns[&1])
      |> case do
        %Turn{child_work_id: child_work_id} -> child_work_id
        _ -> nil
      end

    %{
      conversation_id: state.conversation.id,
      managed_repo_id: state.conversation.managed_repo_id,
      work_item_id: state.conversation.work_item_id,
      status: state.status,
      admission_paused: state.admission_paused,
      child_execution_paused: state.child_execution_paused,
      active_turn_id: state.active_turn_id,
      active_turn: summarize_turn(state.turns[state.active_turn_id]),
      active_child_work_id: active_child_work_id,
      active_child_work: summarize_child_work(state.child_works[active_child_work_id]),
      queued_turn_ids: state.work_queue,
      turns:
        state.turn_order
        |> Enum.map(&Map.fetch!(state.turns, &1))
        |> Enum.map(&summarize_turn/1),
      child_works:
        state.child_work_order
        |> Enum.map(&Map.fetch!(state.child_works, &1))
        |> Enum.map(&summarize_child_work/1),
      control_history: state.control_history
    }
  end

  defp summarize_turn(nil), do: nil

  defp summarize_turn(%Turn{} = turn) do
    %{
      id: turn.id,
      command_id: turn.command_id,
      command_type: turn.command_type,
      child_work_id: turn.child_work_id,
      state: turn.state,
      supersedes_turn_id: turn.supersedes_turn_id,
      superseded_by_turn_id: turn.superseded_by_turn_id,
      inserted_at: turn.inserted_at,
      started_at: turn.started_at,
      completed_at: turn.completed_at,
      lifecycle: turn.lifecycle,
      payload: turn.payload
    }
  end

  defp summarize_child_work(nil), do: nil

  defp summarize_child_work(%ChildWork{} = child_work) do
    %{
      id: child_work.id,
      conversation_id: child_work.conversation_id,
      managed_repo_id: child_work.managed_repo_id,
      work_item_id: child_work.work_item_id,
      turn_id: child_work.turn_id,
      tool_call_id: child_work.tool_call_id,
      kind: child_work.kind,
      state: child_work.state,
      inserted_at: child_work.inserted_at,
      started_at: child_work.started_at,
      completed_at: child_work.completed_at,
      result: child_work.result,
      error: child_work.error,
      lifecycle: child_work.lifecycle
    }
  end

  defp control_entry(command) do
    %{
      id: command.id,
      type: command.raw_type,
      class: command.class,
      admitted_at: command.admitted_at,
      payload: command.payload
    }
  end

  defp stop_turn(state, payload) do
    case target_turn(state, payload) do
      {:ok, %Turn{} = turn} ->
        request_turn_cancellation(state, turn)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cancel_tool(state, payload) do
    with {:ok, child_work_id} <- target_child_work_id(state, payload),
         {:ok, pid} <- fetch_child_worker_pid(state, child_work_id),
         {:ok, next_state} <- mark_parent_turn_cancelling(state, child_work_id),
         {:ok, updated_child_work} <- ChildWorker.request_cancel(pid) do
      apply_child_work_update(next_state, updated_child_work)
    end
  end

  defp steer_turn(state, normalized_command) do
    with {:ok, target_turn} <- target_turn(state, normalized_command.payload),
         {:ok, state_after_target} <- mark_turn_superseding(state, target_turn),
         {:ok, replacement_turn} <- build_replacement_turn(state_after_target, normalized_command, target_turn.id),
         {:ok, queued_state} <- enqueue_priority_turn(state_after_target, replacement_turn) do
      update_superseded_reference(queued_state, target_turn.id, replacement_turn.id)
    end
  end

  defp request_turn_cancellation(state, %Turn{state: :queued, id: turn_id} = turn) do
    with {:ok, cancelled_turn} <- Turn.transition(turn, :cancelled) do
      state
      |> put_in([:turns, turn_id], cancelled_turn)
      |> update_in([:work_queue], &Enum.reject(&1, fn queued_turn_id -> queued_turn_id == turn_id end))
      |> then(&{:ok, &1})
    end
  end

  defp request_turn_cancellation(state, %Turn{} = turn) do
    with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling),
         {:ok, next_state} <- put_turn(state, cancelling_turn) do
      case turn.child_work_id do
        child_work_id when is_binary(child_work_id) ->
          cancel_tool(next_state, %{"child_work_id" => child_work_id})

        _ ->
          with {:ok, cancelled_turn} <- Turn.transition(cancelling_turn, :cancelled) do
            apply_turn_transition(next_state, cancelled_turn)
          end
      end
    end
  end

  defp mark_parent_turn_cancelling(state, child_work_id) do
    child_work = Map.fetch!(state.child_works, child_work_id)
    turn = Map.fetch!(state.turns, child_work.turn_id)

    case turn.state do
      :running ->
        with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling) do
          put_turn(state, cancelling_turn)
        end

      :awaiting_input ->
        with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling) do
          put_turn(state, cancelling_turn)
        end

      _ ->
        {:ok, state}
    end
  end

  defp mark_turn_superseding(state, %Turn{state: :queued, id: turn_id} = turn) do
    with {:ok, superseded_turn} <- Turn.transition(turn, :superseded) do
      state
      |> put_in([:turns, turn_id], superseded_turn)
      |> update_in([:work_queue], &Enum.reject(&1, fn queued_turn_id -> queued_turn_id == turn_id end))
      |> then(&{:ok, &1})
    end
  end

  defp mark_turn_superseding(state, %Turn{} = turn) do
    with {:ok, superseding_turn} <- Turn.transition(turn, :superseding),
         {:ok, next_state} <- put_turn(state, superseding_turn) do
      case turn.child_work_id do
        child_work_id when is_binary(child_work_id) ->
          with {:ok, pid} <- fetch_child_worker_pid(next_state, child_work_id),
               {:ok, updated_child_work} <- ChildWorker.request_cancel(pid) do
            apply_child_work_update(next_state, updated_child_work)
          end

        _ ->
          with {:ok, superseded_turn} <- Turn.transition(superseding_turn, :superseded) do
            apply_turn_transition(next_state, superseded_turn)
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
     |> put_in([:turns, turn.id], turn)
     |> update_in([:turn_order], &(&1 ++ [turn.id]))
     |> update_in([:work_queue], &[turn.id | &1])}
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
end
