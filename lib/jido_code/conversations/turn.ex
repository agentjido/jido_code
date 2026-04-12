defmodule JidoCode.Conversations.Turn do
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  @moduledoc """
  Baseline turn state tracked by the conversation coordinator.
  """

  @enforce_keys [:id, :conversation_id, :command_id, :command_type, :state, :payload, :inserted_at]
  defstruct [
    :id,
    :conversation_id,
    :command_id,
    :command_type,
    :child_work_id,
    :state,
    :payload,
    :inserted_at,
    :started_at,
    :completed_at,
    :supersedes_turn_id,
    lifecycle: []
  ]

  @states [:queued, :running, :awaiting_input, :completed, :cancelled, :superseded, :failed]
  @terminal_states [:completed, :cancelled, :superseded, :failed]
  @transitions %{
    queued: [:running, :cancelled, :superseded, :failed],
    running: [:awaiting_input, :completed, :cancelled, :superseded, :failed],
    awaiting_input: [:running, :completed, :cancelled, :superseded, :failed],
    completed: [],
    cancelled: [],
    superseded: [],
    failed: []
  }

  @type t :: %__MODULE__{}

  @spec states() :: [atom()]
  def states, do: @states

  @spec terminal_state?(atom()) :: boolean()
  def terminal_state?(state), do: state in @terminal_states

  @spec new(String.t(), map(), map()) :: t()
  def new(conversation_id, command, attrs \\ %{}) do
    inserted_at = command.admitted_at

    %__MODULE__{
      id: Ecto.UUID.generate(),
      conversation_id: conversation_id,
      command_id: command.id,
      command_type: command.raw_type,
      state: :queued,
      payload: command.payload,
      inserted_at: inserted_at,
      supersedes_turn_id: Map.get(attrs, :supersedes_turn_id) || Map.get(attrs, "supersedes_turn_id"),
      lifecycle: [lifecycle_entry(:queued, inserted_at)]
    }
  end

  @spec transition(t(), atom()) :: {:ok, t()} | {:error, :invalid_transition}
  def transition(%__MODULE__{} = turn, next_state) when next_state in @states do
    if next_state in Map.get(@transitions, turn.state, []) do
      at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok,
       %{
         turn
         | state: next_state,
           started_at: turn.started_at || if(next_state == :running, do: at, else: turn.started_at),
           completed_at: if(terminal_state?(next_state), do: at, else: turn.completed_at),
           lifecycle: turn.lifecycle ++ [lifecycle_entry(next_state, at)]
       }}
    else
      {:error, :invalid_transition}
    end
  end

  def transition(_turn, _next_state), do: {:error, :invalid_transition}

  defp lifecycle_entry(state, at), do: %{"state" => Atom.to_string(state), "at" => DateTime.to_iso8601(at)}
end
