defmodule JidoCode.Conversations.ChildWork do
  # covers: architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
  # covers: architecture.conversation_orchestration.cancellation_lifecycle_is_evented
  @moduledoc """
  Product-owned child execution contract for long-running conversation work.

  Child work runs outside the coordinator mailbox while preserving explicit
  ownership metadata and cancellation lifecycle state.
  """

  alias JidoCode.Conversations.{Conversation, Turn}

  @states [:queued, :running, :cancel_requested, :cancel_acknowledged, :completed, :cancelled, :cancel_failed, :failed]
  @terminal_states [:completed, :cancelled, :cancel_failed, :failed]
  @settlement_states [:completed, :cancelled, :cancel_failed, :failed]
  @transitions %{
    queued: [:running],
    running: [:cancel_requested, :completed, :cancelled, :cancel_failed, :failed],
    cancel_requested: [:cancel_acknowledged, :completed, :cancelled, :cancel_failed, :failed],
    cancel_acknowledged: [:completed, :cancelled, :cancel_failed, :failed],
    completed: [],
    cancelled: [],
    cancel_failed: [],
    failed: []
  }

  @enforce_keys [
    :id,
    :conversation_id,
    :managed_repo_id,
    :turn_id,
    :tool_call_id,
    :kind,
    :state,
    :inserted_at
  ]
  defstruct [
    :id,
    :conversation_id,
    :managed_repo_id,
    :work_item_id,
    :actor,
    :turn_id,
    :tool_call_id,
    :kind,
    :state,
    :inserted_at,
    :started_at,
    :completed_at,
    :result,
    :error,
    lifecycle: []
  ]

  @type settlement :: :completed | :cancelled | :cancel_failed | :failed
  @type t :: %__MODULE__{}

  @spec new(Conversation.t(), Turn.t(), map()) :: t()
  def new(%Conversation{} = conversation, %Turn{} = turn, attrs \\ %{}) do
    inserted_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    payload = Map.get(turn, :payload, %{})

    %__MODULE__{
      id: Ecto.UUID.generate(),
      conversation_id: conversation.id,
      managed_repo_id: conversation.managed_repo_id,
      work_item_id: conversation.work_item_id,
      actor: normalize_map(Map.get(turn, :actor)),
      turn_id: turn.id,
      tool_call_id: optional_string(map_get(attrs, :tool_call_id) || map_get(payload, :tool_call_id)) || Ecto.UUID.generate(),
      kind: optional_string(map_get(attrs, :kind) || map_get(payload, :execution_kind)) || "tool_call",
      state: :queued,
      inserted_at: inserted_at,
      lifecycle: [lifecycle_entry(:queued, inserted_at)]
    }
  end

  @spec from_summary(map()) :: t()
  def from_summary(summary) when is_map(summary) do
    %__MODULE__{
      id: normalize_optional_string(map_get(summary, :id)) || Ecto.UUID.generate(),
      conversation_id: normalize_optional_string(map_get(summary, :conversation_id)),
      managed_repo_id: normalize_optional_string(map_get(summary, :managed_repo_id)),
      work_item_id: normalize_optional_string(map_get(summary, :work_item_id)),
      actor: normalize_map(map_get(summary, :actor)),
      turn_id: normalize_optional_string(map_get(summary, :turn_id)),
      tool_call_id: normalize_optional_string(map_get(summary, :tool_call_id)),
      kind: normalize_optional_string(map_get(summary, :kind)) || "tool_call",
      state: normalize_state(map_get(summary, :state)),
      inserted_at: normalize_datetime(map_get(summary, :inserted_at)),
      started_at: normalize_optional_datetime(map_get(summary, :started_at)),
      completed_at: normalize_optional_datetime(map_get(summary, :completed_at)),
      result: normalize_optional_map(map_get(summary, :result)),
      error: normalize_optional_map(map_get(summary, :error)),
      lifecycle: normalize_lifecycle(map_get(summary, :lifecycle))
    }
  end

  @spec terminal_state?(atom()) :: boolean()
  def terminal_state?(state), do: state in @terminal_states

  @spec start(t()) :: {:ok, t()} | {:error, :invalid_child_work_transition}
  def start(%__MODULE__{} = child_work) do
    transition(child_work, :running)
  end

  @spec request_cancel(t()) :: {:ok, t()} | {:error, :child_work_already_settled | :invalid_child_work_transition}
  def request_cancel(%__MODULE__{state: state}) when state in @terminal_states,
    do: {:error, :child_work_already_settled}

  def request_cancel(%__MODULE__{} = child_work) do
    transition(child_work, :cancel_requested)
  end

  @spec acknowledge_cancel(t()) :: {:ok, t()} | {:error, :invalid_child_work_transition}
  def acknowledge_cancel(%__MODULE__{} = child_work) do
    transition(child_work, :cancel_acknowledged)
  end

  @spec settle(t(), settlement(), map()) :: {:ok, t()} | {:error, :child_work_already_settled | :invalid_child_work_transition}
  def settle(%__MODULE__{state: state}, _outcome, _attrs) when state in @terminal_states,
    do: {:error, :child_work_already_settled}

  def settle(%__MODULE__{} = child_work, outcome, attrs \\ %{}) when outcome in @settlement_states do
    with {:ok, transitioned} <- transition(child_work, outcome) do
      {:ok,
       %{
         transitioned
         | result: normalize_map(map_get(attrs, :result)),
           error: normalize_error(outcome, attrs)
       }}
    end
  end

  def settle(%__MODULE__{}, _outcome, _attrs), do: {:error, :invalid_child_work_transition}

  defp transition(%__MODULE__{} = child_work, next_state) when next_state in @states do
    if next_state in Map.get(@transitions, child_work.state, []) do
      at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok,
       %{
         child_work
         | state: next_state,
           started_at: child_work.started_at || if(next_state == :running, do: at, else: child_work.started_at),
           completed_at: if(terminal_state?(next_state), do: at, else: child_work.completed_at),
           lifecycle: child_work.lifecycle ++ [lifecycle_entry(next_state, at)]
       }}
    else
      {:error, :invalid_child_work_transition}
    end
  end

  defp transition(_child_work, _next_state), do: {:error, :invalid_child_work_transition}

  defp lifecycle_entry(state, at), do: %{"state" => Atom.to_string(state), "at" => DateTime.to_iso8601(at)}

  defp normalize_error(outcome, attrs) when outcome in [:failed, :cancel_failed] do
    normalize_map(map_get(attrs, :error))
  end

  defp normalize_error(_outcome, _attrs), do: nil

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

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(_value), do: nil

  defp normalize_optional_string(value), do: optional_string(value)

  defp normalize_state(state) when state in @states, do: state

  defp normalize_state(state) when is_binary(state) do
    case state do
      "queued" -> :queued
      "running" -> :running
      "cancel_requested" -> :cancel_requested
      "cancel_acknowledged" -> :cancel_acknowledged
      "completed" -> :completed
      "cancelled" -> :cancelled
      "cancel_failed" -> :cancel_failed
      "failed" -> :failed
      _other -> :queued
    end
  end

  defp normalize_state(_state), do: :queued

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

  defp normalize_optional_map(nil), do: nil
  defp normalize_optional_map(value), do: normalize_map(value)

  defp normalize_lifecycle(value) when is_list(value), do: Enum.filter(value, &is_map/1)
  defp normalize_lifecycle(_value), do: []
end
