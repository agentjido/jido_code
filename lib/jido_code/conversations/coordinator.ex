defmodule JidoCode.Conversations.Coordinator do
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  @moduledoc """
  Coordinator process for one active conversation.

  Owns command admission, baseline turn lifecycle, and product-readable snapshots.
  """

  use GenServer

  alias JidoCode.Conversations.{Command, Conversation, Turn}

  @type state :: %{
          conversation: Conversation.t(),
          status: atom(),
          active_turn_id: String.t() | nil,
          work_queue: [String.t()],
          turns: %{String.t() => Turn.t()},
          turn_order: [String.t()],
          control_history: [map()]
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
       active_turn_id: nil,
       work_queue: [],
       turns: %{},
       turn_order: [],
       control_history: []
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

  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, snapshot_from_state(state)}, state}
  end

  defp admit_normalized_command(state, %{class: :work} = normalized_command) do
    turn = Turn.new(state.conversation.id, normalized_command)

    next_state =
      state
      |> put_in([:turns, turn.id], turn)
      |> update_in([:turn_order], &(&1 ++ [turn.id]))
      |> update_in([:work_queue], &(&1 ++ [turn.id]))
      |> maybe_activate_next_turn()

    {:ok, next_state}
  end

  defp admit_normalized_command(state, %{class: :control} = normalized_command) do
    next_state =
      state
      |> update_in([:control_history], &(&1 ++ [control_entry(normalized_command)]))
      |> apply_baseline_control(normalized_command)
      |> maybe_activate_next_turn()

    {:ok, next_state}
  end

  defp apply_baseline_control(state, %{type: :session_pause}) do
    %{state | status: :paused, conversation: %{state.conversation | status: :paused}}
  end

  defp apply_baseline_control(state, %{type: :session_resume}) do
    %{state | status: :active, conversation: %{state.conversation | status: :active}}
  end

  defp apply_baseline_control(state, _normalized_command), do: state

  defp maybe_activate_next_turn(%{status: :paused} = state), do: state
  defp maybe_activate_next_turn(%{active_turn_id: active_turn_id} = state) when not is_nil(active_turn_id), do: state

  defp maybe_activate_next_turn(%{work_queue: [next_turn_id | remaining_turn_ids]} = state) do
    %Turn{} = next_turn = Map.fetch!(state.turns, next_turn_id)
    {:ok, running_turn} = Turn.transition(next_turn, :running)

    state
    |> put_in([:turns, next_turn_id], running_turn)
    |> Map.put(:active_turn_id, next_turn_id)
    |> Map.put(:work_queue, remaining_turn_ids)
  end

  defp maybe_activate_next_turn(state), do: state

  defp apply_turn_transition(state, %Turn{} = updated_turn) do
    next_state = put_in(state, [:turns, updated_turn.id], updated_turn)

    if Turn.terminal_state?(updated_turn.state) and next_state.active_turn_id == updated_turn.id do
      {:ok, next_state |> Map.put(:active_turn_id, nil) |> maybe_activate_next_turn()}
    else
      {:ok, next_state}
    end
  end

  defp snapshot_from_state(state) do
    %{
      conversation_id: state.conversation.id,
      managed_repo_id: state.conversation.managed_repo_id,
      work_item_id: state.conversation.work_item_id,
      status: state.status,
      active_turn_id: state.active_turn_id,
      active_turn: summarize_turn(state.turns[state.active_turn_id]),
      queued_turn_ids: state.work_queue,
      turns:
        state.turn_order
        |> Enum.map(&Map.fetch!(state.turns, &1))
        |> Enum.map(&summarize_turn/1),
      control_history: state.control_history
    }
  end

  defp summarize_turn(nil), do: nil

  defp summarize_turn(%Turn{} = turn) do
    %{
      id: turn.id,
      command_id: turn.command_id,
      command_type: turn.command_type,
      state: turn.state,
      supersedes_turn_id: turn.supersedes_turn_id,
      inserted_at: turn.inserted_at,
      started_at: turn.started_at,
      completed_at: turn.completed_at,
      lifecycle: turn.lifecycle,
      payload: turn.payload
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
end
