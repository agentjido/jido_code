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
    :actor,
    :child_work_id,
    :state,
    :payload,
    :inserted_at,
    :started_at,
    :completed_at,
    :supersedes_turn_id,
    :superseded_by_turn_id,
    lifecycle: []
  ]

  @states [:queued, :running, :awaiting_input, :cancelling, :superseding, :completed, :cancelled, :superseded, :failed]
  @terminal_states [:completed, :cancelled, :superseded, :failed]
  @transitions %{
    queued: [:running, :cancelled, :superseded, :failed],
    running: [:awaiting_input, :cancelling, :superseding, :completed, :cancelled, :superseded, :failed],
    awaiting_input: [:running, :cancelling, :superseding, :completed, :cancelled, :superseded, :failed],
    cancelling: [:completed, :cancelled, :failed],
    superseding: [:completed, :superseded, :failed],
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
      actor: normalize_map(Map.get(command, :actor) || Map.get(command, "actor")),
      state: :queued,
      payload: command.payload,
      inserted_at: inserted_at,
      supersedes_turn_id: Map.get(attrs, :supersedes_turn_id) || Map.get(attrs, "supersedes_turn_id"),
      superseded_by_turn_id: Map.get(attrs, :superseded_by_turn_id) || Map.get(attrs, "superseded_by_turn_id"),
      lifecycle: [lifecycle_entry(:queued, inserted_at)]
    }
  end

  @spec from_summary(map()) :: t()
  def from_summary(summary) when is_map(summary) do
    %__MODULE__{
      id: normalize_optional_string(map_get(summary, :id)) || Ecto.UUID.generate(),
      conversation_id: normalize_optional_string(map_get(summary, :conversation_id)),
      command_id: normalize_optional_string(map_get(summary, :command_id)),
      command_type: normalize_optional_string(map_get(summary, :command_type)),
      actor: normalize_map(map_get(summary, :actor)),
      child_work_id: normalize_optional_string(map_get(summary, :child_work_id)),
      state: normalize_state(map_get(summary, :state)),
      payload: normalize_map(map_get(summary, :payload)),
      inserted_at: normalize_datetime(map_get(summary, :inserted_at)),
      started_at: normalize_optional_datetime(map_get(summary, :started_at)),
      completed_at: normalize_optional_datetime(map_get(summary, :completed_at)),
      supersedes_turn_id: normalize_optional_string(map_get(summary, :supersedes_turn_id)),
      superseded_by_turn_id: normalize_optional_string(map_get(summary, :superseded_by_turn_id)),
      lifecycle: normalize_lifecycle(map_get(summary, :lifecycle))
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

  defp map_get(map, key) when is_map(map) do
    string_key =
      case key do
        atom when is_atom(atom) -> Atom.to_string(atom)
        binary when is_binary(binary) -> binary
      end

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

  defp normalize_state(state) when state in @states, do: state

  defp normalize_state(state) when is_binary(state) do
    case state do
      "queued" -> :queued
      "running" -> :running
      "awaiting_input" -> :awaiting_input
      "cancelling" -> :cancelling
      "superseding" -> :superseding
      "completed" -> :completed
      "cancelled" -> :cancelled
      "superseded" -> :superseded
      "failed" -> :failed
      _other -> :queued
    end
  end

  defp normalize_state(_state), do: :queued

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :microsecond)
      _other -> DateTime.utc_now() |> DateTime.truncate(:microsecond)
    end
  end

  defp normalize_datetime(_value), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp normalize_optional_datetime(nil), do: nil
  defp normalize_optional_datetime(value), do: normalize_datetime(value)

  defp normalize_lifecycle(value) when is_list(value), do: Enum.filter(value, &is_map/1)
  defp normalize_lifecycle(_value), do: []
end
