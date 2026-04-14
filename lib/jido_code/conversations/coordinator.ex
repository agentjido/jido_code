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
  alias JidoCode.Conversations.WorkResolution

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

  def start_link({%Conversation{} = conversation, opts}) when is_list(opts) do
    GenServer.start_link(__MODULE__, {conversation, opts}, name: via_tuple(conversation.id))
  end

  def start_link(%Conversation{} = conversation), do: start_link({conversation, []})

  @spec via_tuple(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(conversation_id),
    do: {:via, Registry, {JidoCode.Conversations.Registry, conversation_id}}

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
    GenServer.call(
      via_tuple(conversation_id),
      {:settle_child_work, child_work_id, outcome, attrs, actor}
    )
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
  def init({%Conversation{} = conversation, opts}) when is_list(opts) do
    maybe_allow_test_sandbox(
      Keyword.get(opts, :sandbox_owner),
      Keyword.get(opts, :starter_pid)
    )

    state =
      case Persistence.restore_state(conversation) do
        {:ok, restored_state} when is_map(restored_state) -> restored_state
        _other -> fresh_state(conversation)
      end

    {:ok, state}
  end

  def init(%Conversation{} = conversation), do: init({conversation, []})

  @impl true
  def terminate(_reason, state) do
    state
    |> Map.get(:child_worker_pids, %{})
    |> Map.values()
    |> Enum.filter(&is_pid/1)
    |> Enum.each(&maybe_terminate_child_worker/1)

    :ok
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
    with {:ok, updated_child_work} <-
           settle_child_work_runtime(state, child_work_id, outcome, attrs),
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

  @impl true
  def handle_info({:begin_child_runtime, child_work_id}, state) when is_binary(child_work_id) do
    case maybe_begin_child_runtime(state, child_work_id) do
      {:ok, next_state} -> {:noreply, next_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp admit_normalized_command(state, %{class: :work, type: :turn_submit} = normalized_command) do
    turn = Turn.new(state.conversation.id, normalized_command)

    state
    |> append_command_message_event(normalized_command)
    |> update_in([:turn_order], &(&1 ++ [turn.id]))
    |> update_in([:work_queue], &(&1 ++ [turn.id]))
    |> store_turn(turn, actor: normalized_command.actor, message_id: normalized_command.id)
    |> maybe_append_turn_intent_event(turn, normalized_command)
    |> maybe_activate_next_turn()
  end

  defp admit_normalized_command(state, %{class: :work, type: :turn_resume} = normalized_command) do
    with {:ok, resumable_turn} <- resumable_turn(state, normalized_command.payload),
         resume_state = append_command_message_event(state, normalized_command),
         {:ok, resumed_turn} <- Turn.transition(resumable_turn, :running),
         resumed_turn =
           with_resume_payload(resumed_turn, state, normalized_command.payload),
         next_state <-
           maybe_clear_child_work_pending_input(
             resume_state,
             resumable_turn.child_work_id,
             normalized_command.actor
           ),
         {:ok, applied_state} <-
           apply_turn_transition(
             next_state,
             resumed_turn,
             normalized_command.actor,
             normalized_command.payload
           ),
         {:ok, resumed_state} <- maybe_schedule_runtime_for_turn(applied_state, resumed_turn.id) do
      {:ok, resumed_state}
    end
  end

  defp admit_normalized_command(
         state,
         %{class: :work, type: :tool_result_submit} = normalized_command
       ) do
    apply_tool_result_command(state, normalized_command)
  end

  defp admit_normalized_command(state, %{class: :control} = normalized_command) do
    with {:ok, applied_state} <-
           state
           |> append_command_message_event(normalized_command)
           |> apply_control_command(normalized_command),
         {:ok, next_state} <-
           applied_state
           |> update_in(
             [:control_history],
             &(&1 ++ [control_entry(normalized_command, applied_state)])
           )
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
    cancel_tool(
      state,
      normalized_command.payload,
      normalized_command.actor,
      normalized_command.id
    )
  end

  defp apply_control_command(state, %{type: :turn_steer} = normalized_command) do
    steer_turn(state, normalized_command)
  end

  defp apply_control_command(state, _normalized_command), do: {:ok, state}

  defp maybe_activate_next_turn({:ok, state}), do: maybe_activate_next_turn(state)

  defp maybe_activate_next_turn(%{status: :paused} = state), do: {:ok, state}
  defp maybe_activate_next_turn(%{admission_paused: true} = state), do: {:ok, state}

  defp maybe_activate_next_turn(%{active_turn_id: active_turn_id} = state)
       when not is_nil(active_turn_id), do: {:ok, state}

  defp maybe_activate_next_turn(%{work_queue: [next_turn_id | remaining_turn_ids]} = state) do
    with {:ok, prepared_state} <- maybe_prepare_runtime_scope(state, next_turn_id),
         %Turn{} = next_turn <- Map.fetch!(prepared_state.turns, next_turn_id),
         {:ok, running_turn} <- Turn.transition(next_turn, :running),
         child_work <- ChildWork.new(prepared_state.conversation, running_turn),
         {:ok, pid} <- ChildWorker.start(child_work),
         {:ok, running_child_work} <- ChildWorker.snapshot(pid) do
      running_turn = %{running_turn | child_work_id: running_child_work.id}

      next_state =
        prepared_state
       |> Map.put(:active_turn_id, next_turn_id)
       |> Map.put(:work_queue, remaining_turn_ids)
       |> update_in([:child_work_order], &(&1 ++ [running_child_work.id]))
       |> put_in([:child_worker_pids, running_child_work.id], pid)
       |> store_turn(running_turn, actor: running_turn.actor, message_id: running_turn.command_id)
       |> store_child_work(running_child_work,
         actor: running_child_work.actor,
         message_id: running_turn.command_id
       )

      maybe_schedule_runtime_for_turn(next_state, running_turn.id)
    end
  end

  defp maybe_activate_next_turn(state), do: {:ok, state}

  defp maybe_prepare_runtime_scope(state, next_turn_id) do
    turn = Map.fetch!(state.turns, next_turn_id)

    if auto_runtime_enabled?(state.conversation) and is_nil(state.conversation.work_item_id) do
      case WorkResolution.ensure_turn_attachment(
             state.conversation,
             turn,
             Snapshot.from_state(state).shared_context,
             actor: turn.actor
           ) do
        {:ok, %{conversation: %Conversation{} = updated_conversation}} ->
          {:ok, %{state | conversation: updated_conversation}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_schedule_runtime_for_turn(state, turn_id) when is_binary(turn_id) do
    if auto_runtime_enabled?(state.conversation) do
      case Map.get(state.turns, turn_id) do
        %Turn{child_work_id: child_work_id, state: :running} when is_binary(child_work_id) ->
          send(self(), {:begin_child_runtime, child_work_id})
          {:ok, state}

        _other ->
          {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_schedule_runtime_for_turn(state, _turn_id), do: {:ok, state}

  defp maybe_begin_child_runtime(state, child_work_id) do
    with {:ok, pid, next_state} <- ensure_child_worker_for_runtime(state, child_work_id),
         %ChildWork{} = child_work <- Map.fetch!(next_state.child_works, child_work_id),
         %Turn{} = turn <- Map.fetch!(next_state.turns, child_work.turn_id),
         runtime_spec <- runtime_spec(next_state, turn, child_work),
         {:ok, _child_work} <- ChildWorker.begin_runtime(pid, runtime_spec) do
      {:ok, next_state}
    end
  end

  defp ensure_child_worker_for_runtime(state, child_work_id) do
    case Map.fetch(state.child_worker_pids, child_work_id) do
      {:ok, pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid, state}
        else
          restart_child_worker_for_runtime(state, child_work_id)
        end

      {:ok, _stale_pid} ->
        restart_child_worker_for_runtime(state, child_work_id)

      :error ->
        restart_child_worker_for_runtime(state, child_work_id)
    end
  end

  defp restart_child_worker_for_runtime(state, child_work_id) do
    case Map.fetch(state.child_works, child_work_id) do
      {:ok, %ChildWork{} = child_work} ->
        with {:ok, pid} <- ChildWorker.start(child_work) do
          {:ok, pid, put_in(state, [:child_worker_pids, child_work_id], pid)}
        end

      :error ->
        {:error, :child_work_not_found}
    end
  end

  defp runtime_spec(state, turn, child_work) do
    shared_context = Snapshot.from_state(state).shared_context

    %{
      conversation_id: state.conversation.id,
      managed_repo_id: state.conversation.managed_repo_id,
      work_item_id: state.conversation.work_item_id,
      child_work_id: child_work.id,
      turn_id: turn.id,
      instruction: runtime_instruction(turn),
      command_type: turn.command_type,
      actor: turn.actor,
      objective: state.conversation.objective,
      source: state.conversation.source,
      source_metadata: normalize_map(state.conversation.source_metadata),
      conversation_metadata: normalize_map(state.conversation.conversation_metadata),
      shared_context: shared_context,
      turn_payload: normalize_map(turn.payload),
      child_work_result: normalize_map(child_work.result),
      sandbox_owner: Process.get({JidoCode.Repo, :sandbox_owner}),
      starter_pid: self()
    }
  end

  defp runtime_instruction(%Turn{payload: payload}) do
    payload = normalize_map(payload)

    case Map.get(payload, "clarification_resume") do
      %{} = clarification_resume ->
        Map.get(clarification_resume, "response") ||
          Map.get(payload, "instruction") ||
          Map.get(payload, "reason") ||
          "Continue the repository conversation."

      _other ->
        Map.get(payload, "instruction") || Map.get(payload, "reason") || "Continue the repository conversation."
    end
  end

  defp with_resume_payload(%Turn{} = turn, state, payload) when is_map(payload) do
    clarification_resume =
      %{}
      |> maybe_put("response", optional_string(Map.get(payload, "response")))
      |> maybe_put("prompt", resume_prompt(state, turn, payload))

    if clarification_resume == %{} do
      turn
    else
      %{turn | payload: Map.put(normalize_map(turn.payload), "clarification_resume", clarification_resume)}
    end
  end

  defp with_resume_payload(%Turn{} = turn, _state, _payload), do: turn

  defp resume_prompt(state, %Turn{} = turn, payload) when is_map(payload) do
    case optional_string(Map.get(payload, "prompt")) do
      nil ->
        state
        |> pending_clarification_for_turn(turn.id)
        |> case do
          %{"prompt" => %{"prompt" => prompt}} -> prompt
          %{"prompt" => %{"details" => %{"prompt" => prompt}}} -> prompt
          %{"prompt" => prompt} when is_binary(prompt) -> prompt
          _other -> nil
        end

      prompt ->
        prompt
    end
  end

  defp pending_clarification_for_turn(state, turn_id) when is_binary(turn_id) do
    state
    |> Snapshot.from_state()
    |> Map.get(:shared_context, %{})
    |> Map.get("pending_clarification")
    |> case do
      %{"turn_id" => ^turn_id} = pending_clarification -> pending_clarification
      _other -> nil
    end
  end

  defp pending_clarification_for_turn(_state, _turn_id), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp auto_runtime_enabled?(%Conversation{source: "project_detail"}), do: true
  defp auto_runtime_enabled?(_conversation), do: false

  defp apply_tool_result_command(state, normalized_command) do
    with {:ok, %ChildWork{} = child_work} <- target_child_work(state, normalized_command.payload),
         {:ok, %Turn{} = turn} <- turn_for_child_work(state, child_work),
         {:ok, result_kind} <- tool_result_kind(normalized_command.payload),
         {:ok, next_state} <-
           apply_tool_result_kind(
             state,
             turn,
             child_work,
             result_kind,
             normalized_command
           ) do
      {:ok, next_state}
    end
  end

  defp apply_tool_result_kind(
         state,
         _turn,
         %ChildWork{} = child_work,
         :progress,
         normalized_command
       ) do
    with {:ok, updated_child_work} <-
           ChildWork.record_update(child_work, :progress, normalized_command.payload) do
      next_state = put_in(state, [:child_works, updated_child_work.id], updated_child_work)

      {:ok,
       append_child_work_runtime_event(
         next_state,
         "tool.progress",
         updated_child_work,
         normalized_command.actor,
         normalized_command.payload,
         normalized_command.id
       )}
    end
  end

  defp apply_tool_result_kind(
         state,
         _turn,
         %ChildWork{} = child_work,
         :stdout,
         normalized_command
       ) do
    with {:ok, updated_child_work} <-
           ChildWork.record_update(child_work, :stdout, normalized_command.payload) do
      next_state = put_in(state, [:child_works, updated_child_work.id], updated_child_work)

      {:ok,
       append_child_work_runtime_event(
         next_state,
         "tool.stdout",
         updated_child_work,
         normalized_command.actor,
         normalized_command.payload,
         normalized_command.id
       )}
    end
  end

  defp apply_tool_result_kind(
         state,
         %Turn{} = turn,
         %ChildWork{} = child_work,
         :delta,
         normalized_command
       ) do
    with {:ok, updated_child_work} <-
           ChildWork.record_update(child_work, :delta, normalized_command.payload) do
      next_state = put_in(state, [:child_works, updated_child_work.id], updated_child_work)

      {:ok,
       append_turn_runtime_event(
         next_state,
         "turn.delta",
         %{turn | child_work_id: updated_child_work.id},
         normalized_command.actor,
         normalized_command.payload,
         normalized_command.id,
         updated_child_work
       )}
    end
  end

  defp apply_tool_result_kind(
         state,
         %Turn{} = turn,
         %ChildWork{} = child_work,
         :needs_input,
         normalized_command
       ) do
    with {:ok, updated_child_work} <-
           ChildWork.record_update(child_work, :needs_input, normalized_command.payload) do
      state =
        state
        |> put_in([:child_works, updated_child_work.id], updated_child_work)
        |> append_child_work_runtime_event(
          "tool.needs_input",
          updated_child_work,
          normalized_command.actor,
          normalized_command.payload,
          normalized_command.id
        )

      case turn.state do
        :awaiting_input ->
          {:ok, state}

        _other ->
          with {:ok, awaiting_input_turn} <- Turn.transition(turn, :awaiting_input) do
            apply_turn_transition(
              state,
              awaiting_input_turn,
              normalized_command.actor,
              normalized_command.payload
            )
          end
      end
    end
  end

  defp apply_tool_result_kind(
         state,
         _turn,
         %ChildWork{} = child_work,
         settlement,
         normalized_command
       )
       when settlement in [:completed, :cancelled, :cancel_failed, :failed] do
    with {:ok, updated_child_work} <-
           ChildWork.settle(
             child_work,
             settlement,
             runtime_settlement_attrs(normalized_command.payload)
           ) do
      apply_child_work_update(
        state,
        updated_child_work,
        normalized_command.actor,
        normalized_command.payload
      )
    end
  end

  defp resumable_turn(state, payload) do
    with {:ok, %Turn{} = turn} <- target_turn(state, payload) do
      if turn.state == :awaiting_input do
        {:ok, turn}
      else
        {:error, :turn_not_awaiting_input}
      end
    end
  end

  defp maybe_clear_child_work_pending_input(state, child_work_id, actor)
       when is_binary(child_work_id) do
    case Map.fetch(state.child_works, child_work_id) do
      {:ok, %ChildWork{} = child_work} ->
        {:ok, cleared_child_work} = ChildWork.clear_pending_input(child_work)
        store_child_work(state, cleared_child_work, actor: actor)

      :error ->
        state
    end
  end

  defp maybe_clear_child_work_pending_input(state, _child_work_id, _actor), do: state

  defp apply_turn_transition(state, %Turn{} = updated_turn, actor \\ %{}, attrs \\ %{}) do
    next_state =
      state
      |> store_turn(updated_turn,
        actor: actor,
        payload: attrs,
        message_id: updated_turn.command_id
      )
      |> sync_child_work_with_turn(updated_turn, actor)

    if Turn.terminal_state?(updated_turn.state) and next_state.active_turn_id == updated_turn.id do
      next_state
      |> Map.put(:active_turn_id, nil)
      |> maybe_activate_next_turn()
    else
      {:ok, next_state}
    end
  end

  defp apply_child_work_update(
         state,
         %ChildWork{} = updated_child_work,
         actor \\ %{},
         attrs \\ %{}
       ) do
    next_state =
      state
      |> store_child_work(updated_child_work, actor: actor, payload: attrs)
      |> maybe_drop_child_worker(updated_child_work)

    if ChildWork.terminal_state?(updated_child_work.state) do
      turn = Map.fetch!(next_state.turns, updated_child_work.turn_id)

      with {:ok, settled_turn} <-
             Turn.transition(turn, settled_turn_state(turn, updated_child_work.state)) do
        apply_turn_transition(next_state, settled_turn, actor, attrs)
      end
    else
      {:ok, next_state}
    end
  end

  defp settle_child_work_runtime(state, child_work_id, outcome, attrs) do
    case Map.fetch(state.child_worker_pids, child_work_id) do
      {:ok, pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          try do
            ChildWorker.settle(pid, outcome, attrs)
          catch
            :exit, _reason -> fallback_child_work_settlement(state, child_work_id, outcome, attrs)
          end
        else
          fallback_child_work_settlement(state, child_work_id, outcome, attrs)
        end

      :error ->
        fallback_child_work_settlement(state, child_work_id, outcome, attrs)
    end
  end

  defp fallback_child_work_settlement(state, child_work_id, outcome, attrs) do
    state.child_works
    |> Map.fetch(child_work_id)
    |> case do
      {:ok, %ChildWork{} = child_work} -> ChildWork.settle(child_work, outcome, attrs)
      :error -> {:error, :child_work_not_found}
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

  defp settled_turn_state(_turn, child_work_state),
    do: child_work_terminal_state(child_work_state)

  defp sync_child_work_with_turn(
         state,
         %Turn{state: turn_state, child_work_id: child_work_id},
         actor
       )
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

  defp control_entry(command, state) do
    %{
      id: command.id,
      type: command.raw_type,
      class: command.class,
      admitted_at: command.admitted_at,
      actor: command.actor,
      payload: command.payload
    }
    |> maybe_put(:work_item_id, state.conversation.work_item_id)
    |> maybe_put(
      :work_action,
      map_get(state.conversation.conversation_metadata, "last_work_action")
    )
    |> maybe_put(
      :work_resolution,
      map_get(state.conversation.conversation_metadata, "last_work_resolution")
    )
    |> maybe_put(:attachment_mode, state.conversation.attachment_mode)
    |> maybe_put(:scope, state.conversation.scope)
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
         {:ok, next_state} <-
           mark_parent_turn_cancelling(state, child_work_id, actor, payload, message_id),
         child_work <- Map.fetch!(next_state.child_works, child_work_id),
         final_state <-
           append_child_work_cancel_requested_event(
             next_state,
             child_work,
             actor,
             payload,
             message_id
           ),
         {:ok, updated_child_work} <- ChildWorker.request_cancel(pid) do
      apply_child_work_update(final_state, updated_child_work, actor, payload)
    end
  end

  defp steer_turn(state, normalized_command) do
    with {:ok, target_turn} <- target_turn(state, normalized_command.payload),
         {:ok, state_after_work} <-
           apply_conversation_work_steering(state, normalized_command, target_turn),
         {:ok, state_after_target} <-
           mark_turn_superseding(
             state_after_work,
             target_turn,
             normalized_command.actor,
             normalized_command.payload,
             normalized_command.id
           ),
         {:ok, replacement_turn} <-
           build_replacement_turn(state_after_target, normalized_command, target_turn.id),
         {:ok, queued_state} <- enqueue_priority_turn(state_after_target, replacement_turn) do
      update_superseded_reference(queued_state, target_turn.id, replacement_turn.id)
    end
  end

  defp apply_conversation_work_steering(
         state,
         %{type: :turn_steer} = normalized_command,
         %Turn{} = target_turn
       ) do
    steering_payload =
      normalized_command.payload
      |> Map.put_new("turn_id", target_turn.id)
      |> Map.put_new("command_id", normalized_command.id)
      |> Map.put_new("resolution_command_type", normalized_command.raw_type)

    case JidoCode.Conversations.steer_work(
           state.conversation,
           steering_payload,
           actor: normalized_command.actor,
           shared_context: Snapshot.from_state(state).shared_context
         ) do
      {:ok, %{conversation: %Conversation{} = updated_conversation}} ->
        {:ok, %{state | conversation: updated_conversation}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_conversation_work_steering(state, _normalized_command, _target_turn), do: {:ok, state}

  defp request_turn_cancellation(
         state,
         %Turn{state: :queued, id: turn_id} = turn,
         actor,
         payload,
         message_id
       ) do
    with {:ok, cancelled_turn} <- Turn.transition(turn, :cancelled) do
      state
      |> update_in(
        [:work_queue],
        &Enum.reject(&1, fn queued_turn_id -> queued_turn_id == turn_id end)
      )
      |> store_turn(cancelled_turn, actor: actor, payload: payload, message_id: message_id)
      |> then(&{:ok, &1})
    end
  end

  defp request_turn_cancellation(state, %Turn{} = turn, actor, payload, message_id) do
    with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling) do
      next_state =
        store_turn(state, cancelling_turn, actor: actor, payload: payload, message_id: message_id)

      case turn.child_work_id do
        child_work_id when is_binary(child_work_id) ->
          cancel_tool(
            next_state,
            %{"child_work_id" => child_work_id} |> Map.merge(payload),
            actor,
            message_id
          )

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
          {:ok,
           store_turn(state, cancelling_turn,
             actor: actor,
             payload: payload,
             message_id: message_id
           )}
        end

      :awaiting_input ->
        with {:ok, cancelling_turn} <- Turn.transition(turn, :cancelling) do
          {:ok,
           store_turn(state, cancelling_turn,
             actor: actor,
             payload: payload,
             message_id: message_id
           )}
        end

      _ ->
        {:ok, state}
    end
  end

  defp mark_turn_superseding(
         state,
         %Turn{state: :queued, id: turn_id} = turn,
         actor,
         payload,
         message_id
       ) do
    with {:ok, superseded_turn} <- Turn.transition(turn, :superseded) do
      state
      |> update_in(
        [:work_queue],
        &Enum.reject(&1, fn queued_turn_id -> queued_turn_id == turn_id end)
      )
      |> store_turn(superseded_turn, actor: actor, payload: payload, message_id: message_id)
      |> then(&{:ok, &1})
    end
  end

  defp mark_turn_superseding(state, %Turn{} = turn, actor, payload, message_id) do
    with {:ok, superseding_turn} <- Turn.transition(turn, :superseding) do
      next_state =
        store_turn(state, superseding_turn,
          actor: actor,
          payload: payload,
          message_id: message_id
        )

      case turn.child_work_id do
        child_work_id when is_binary(child_work_id) ->
          with {:ok, pid} <- fetch_child_worker_pid(next_state, child_work_id),
               child_work <- Map.fetch!(next_state.child_works, child_work_id),
               requested_state <-
                 append_child_work_cancel_requested_event(
                   next_state,
                   child_work,
                   actor,
                   payload,
                   message_id
                 ),
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
    {:ok,
     Turn.new(state.conversation.id, normalized_command, %{supersedes_turn_id: supersedes_turn_id})}
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

  defp target_child_work(state, payload) do
    case target_child_work_id(state, payload) do
      {:ok, child_work_id} ->
        case Map.fetch(state.child_works, child_work_id) do
          {:ok, %ChildWork{} = child_work} -> {:ok, child_work}
          :error -> {:error, :child_work_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp turn_for_child_work(state, %ChildWork{} = child_work) do
    case Map.fetch(state.turns, child_work.turn_id) do
      {:ok, %Turn{} = turn} -> {:ok, turn}
      :error -> {:error, :turn_not_found}
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
          %Turn{child_work_id: child_work_id} when is_binary(child_work_id) ->
            {:ok, child_work_id}

          _ ->
            {:error, :child_work_not_found}
        end

      true ->
        {:error, :child_work_not_found}
    end
  end

  defp tool_result_kind(payload) do
    payload
    |> Map.get("kind")
    |> normalize_tool_result_kind()
  end

  defp normalize_tool_result_kind(kind)
       when kind in [
              :progress,
              :stdout,
              :needs_input,
              :delta,
              :completed,
              :cancelled,
              :cancel_failed,
              :failed
            ],
       do: {:ok, kind}

  defp normalize_tool_result_kind(kind) when is_binary(kind) do
    case kind do
      "progress" -> {:ok, :progress}
      "stdout" -> {:ok, :stdout}
      "needs_input" -> {:ok, :needs_input}
      "delta" -> {:ok, :delta}
      "completed" -> {:ok, :completed}
      "cancelled" -> {:ok, :cancelled}
      "cancel_failed" -> {:ok, :cancel_failed}
      "failed" -> {:ok, :failed}
      _other -> {:error, :invalid_tool_result_kind}
    end
  end

  defp normalize_tool_result_kind(_kind), do: {:error, :invalid_tool_result_kind}

  defp runtime_settlement_attrs(payload) do
    %{}
    |> maybe_put("result", map_get(payload, "result"))
    |> maybe_put("error", map_get(payload, "error"))
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

  defp append_child_work_cancel_requested_event(
         state,
         %ChildWork{} = child_work,
         actor,
         payload,
         message_id \\ nil
       ) do
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

  defp maybe_append_child_work_state_event(
         state,
         previous_child_work,
         %ChildWork{} = updated_child_work,
         opts
       ) do
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

  defp append_turn_runtime_event(
         state,
         event_name,
         %Turn{} = turn,
         actor,
         payload,
         message_id,
         child_work \\ nil
       ) do
    append_event(state, event_name, %{
      actor: actor,
      message_id: message_id,
      turn_id: turn.id,
      child_work_id: (child_work && child_work.id) || turn.child_work_id,
      tool_call_id: child_work && child_work.tool_call_id,
      correlation: turn_correlation(turn),
      payload:
        %{
          "state" => Atom.to_string(turn.state),
          "command_type" => turn.command_type
        }
        |> Map.merge(payload)
    })
  end

  defp append_child_work_runtime_event(
         state,
         event_name,
         %ChildWork{} = child_work,
         actor,
         payload,
         message_id
       ) do
    append_event(state, event_name, %{
      actor: actor,
      message_id: message_id,
      turn_id: child_work.turn_id,
      child_work_id: child_work.id,
      tool_call_id: child_work.tool_call_id,
      correlation: child_work_correlation(child_work),
      payload:
        %{
          "state" => Atom.to_string(child_work.state),
          "kind" => child_work.kind
        }
        |> Map.merge(payload)
        |> maybe_put("result", child_work.result)
        |> maybe_put("error", child_work.error)
    })
  end

  defp append_event(state, name, attrs) do
    sequence = state.event_sequence + 1
    event =
      attrs
      |> merge_work_context(state.conversation)
      |> then(&Event.new(state.conversation.id, sequence, name, &1))

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

  defp merge_work_context(attrs, %Conversation{} = conversation) when is_map(attrs) do
    work_resolution =
      conversation.conversation_metadata
      |> map_get("last_work_resolution")
      |> normalize_map()

    work_context =
      %{
        "work_item_id" => conversation.work_item_id,
        "scope" => Atom.to_string(conversation.scope),
        "attachment_mode" => Atom.to_string(conversation.attachment_mode)
      }
      |> maybe_put("work_action", map_get(conversation.conversation_metadata, "last_work_action"))
      |> maybe_put("work_resolution", if(work_resolution == %{}, do: nil, else: work_resolution))

    correlation =
      attrs
      |> map_get(:correlation)
      |> normalize_map()
      |> Map.merge(Map.drop(work_context, ["work_resolution"]))

    payload =
      attrs
      |> map_get(:payload)
      |> normalize_map()
      |> Map.put_new("work_context", work_context)

    attrs
    |> Map.put(:correlation, correlation)
    |> Map.put(:payload, payload)
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

  defp maybe_terminate_child_worker(pid) when is_pid(pid) do
    case Process.whereis(JidoCode.Conversations.ChildSupervisor) do
      supervisor when is_pid(supervisor) ->
        if Process.alive?(pid) do
          try do
            _ = DynamicSupervisor.terminate_child(JidoCode.Conversations.ChildSupervisor, pid)
          catch
            :exit, _reason -> :ok
          end
        else
          :ok
        end

      _other ->
        :ok
    end
  end

  defp maybe_terminate_child_worker(_pid), do: :ok

  defp maybe_allow_test_sandbox(sandbox_owner, starter_pid) do
    [sandbox_owner, starter_pid]
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn owner_pid, :ok ->
      case allow_test_sandbox(owner_pid) do
        :ok -> {:halt, :ok}
        :error -> {:cont, :ok}
      end
    end)
  end

  defp allow_test_sandbox(owner_pid) when is_pid(owner_pid) do
    if Code.ensure_loaded?(Ecto.Adapters.SQL.Sandbox) do
      try do
        Ecto.Adapters.SQL.Sandbox.allow(JidoCode.Repo, owner_pid, self())
        :ok
      rescue
        _exception -> :error
      catch
        _kind, _reason -> :error
      end
    else
      :error
    end
  end

  defp turn_event_name(nil, %Turn{state: :queued}), do: "turn.queued"

  defp turn_event_name(%Turn{state: previous_state}, %Turn{state: next_state})
       when previous_state == next_state, do: nil

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

  defp child_work_event_name(%ChildWork{state: previous_state}, %ChildWork{state: next_state})
       when previous_state == next_state, do: nil

  defp child_work_event_name(_previous_child_work, %ChildWork{state: :running}),
    do: "tool.started"

  defp child_work_event_name(_previous_child_work, %ChildWork{state: :cancel_acknowledged}),
    do: "tool.cancel_acknowledged"

  defp child_work_event_name(_previous_child_work, %ChildWork{state: :completed}),
    do: "tool.completed"

  defp child_work_event_name(_previous_child_work, %ChildWork{state: :cancelled}),
    do: "tool.cancelled"

  defp child_work_event_name(_previous_child_work, %ChildWork{state: :cancel_failed}),
    do: "tool.cancel_failed"

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

  defp map_get(map, key) when is_map(map), do: Map.get(map, key)
  defp map_get(_map, _key), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> optional_string()

  defp optional_string(_value), do: nil
end
