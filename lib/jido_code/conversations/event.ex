defmodule JidoCode.Conversations.Event do
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  @moduledoc """
  Canonical append-only conversation event record.

  Events are product-readable, carry stable identifiers, and are sequenced per
  conversation so LiveView surfaces can recover after reconnects without parsing
  runtime-native transport details.
  """

  @canonical_event_names [
    "conversation.message_added",
    "conversation.status_changed",
    "turn.queued",
    "turn.started",
    "turn.intent_announced",
    "turn.delta",
    "turn.awaiting_input",
    "turn.cancelling",
    "turn.superseding",
    "turn.completed",
    "turn.cancelled",
    "turn.superseded",
    "turn.failed",
    "tool.started",
    "tool.progress",
    "tool.stdout",
    "tool.needs_input",
    "tool.cancel_requested",
    "tool.cancel_acknowledged",
    "tool.completed",
    "tool.cancelled",
    "tool.cancel_failed",
    "tool.failed"
  ]

  @enforce_keys [:id, :sequence, :conversation_id, :name, :occurred_at]
  defstruct [
    :id,
    :sequence,
    :conversation_id,
    :name,
    :occurred_at,
    :actor,
    :message_id,
    :turn_id,
    :child_work_id,
    :tool_call_id,
    correlation: %{},
    payload: %{}
  ]

  @type t :: %__MODULE__{}

  @spec canonical_event_names() :: [String.t()]
  def canonical_event_names, do: @canonical_event_names

  @spec new(String.t(), non_neg_integer(), String.t(), map()) :: t()
  def new(conversation_id, sequence, name, attrs \\ %{})
      when is_binary(conversation_id) and is_integer(sequence) and sequence > 0 and is_binary(name) and is_map(attrs) do
    occurred_at =
      Map.get(attrs, :occurred_at) ||
        Map.get(attrs, "occurred_at") ||
        DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %__MODULE__{
      id: optional_string(map_get(attrs, :id)) || Ecto.UUID.generate(),
      sequence: sequence,
      conversation_id: conversation_id,
      name: name,
      occurred_at: occurred_at,
      actor: normalize_map(map_get(attrs, :actor)),
      message_id: optional_string(map_get(attrs, :message_id)),
      turn_id: optional_string(map_get(attrs, :turn_id)),
      child_work_id: optional_string(map_get(attrs, :child_work_id)),
      tool_call_id: optional_string(map_get(attrs, :tool_call_id)),
      correlation: normalize_map(map_get(attrs, :correlation)),
      payload: normalize_map(map_get(attrs, :payload))
    }
  end

  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = event) do
    %{
      id: event.id,
      sequence: event.sequence,
      conversation_id: event.conversation_id,
      name: event.name,
      occurred_at: event.occurred_at,
      actor: event.actor,
      message_id: event.message_id,
      turn_id: event.turn_id,
      child_work_id: event.child_work_id,
      tool_call_id: event.tool_call_id,
      correlation: event.correlation,
      payload: event.payload
    }
  end

  @spec from_summary(map()) :: t()
  def from_summary(summary) when is_map(summary) do
    %__MODULE__{
      id: optional_string(map_get(summary, :id)) || Ecto.UUID.generate(),
      sequence: normalize_sequence(map_get(summary, :sequence)),
      conversation_id: optional_string(map_get(summary, :conversation_id)),
      name: optional_string(map_get(summary, :name)) || "unknown",
      occurred_at: normalize_datetime(map_get(summary, :occurred_at)),
      actor: normalize_map(map_get(summary, :actor)),
      message_id: optional_string(map_get(summary, :message_id)),
      turn_id: optional_string(map_get(summary, :turn_id)),
      child_work_id: optional_string(map_get(summary, :child_work_id)),
      tool_call_id: optional_string(map_get(summary, :tool_call_id)),
      correlation: normalize_map(map_get(summary, :correlation)),
      payload: normalize_map(map_get(summary, :payload))
    }
  end

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

  defp normalize_sequence(value) when is_integer(value) and value > 0, do: value

  defp normalize_sequence(value) when is_binary(value) do
    case Integer.parse(value) do
      {sequence, ""} when sequence > 0 -> sequence
      _other -> 1
    end
  end

  defp normalize_sequence(_value), do: 1

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :microsecond)
      _other -> DateTime.utc_now() |> DateTime.truncate(:microsecond)
    end
  end

  defp normalize_datetime(_value), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(_value), do: nil
end
