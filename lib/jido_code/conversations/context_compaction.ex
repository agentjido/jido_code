defmodule JidoCode.Conversations.ContextCompaction do
  # covers: architecture.context_compaction_policy.compaction_preserves_required_context
  # covers: architecture.context_compaction_policy.tool_protocol_boundaries_are_preserved
  @moduledoc """
  Conversation-state projection helpers for automatic context compaction.

  The durable conversation event log remains append-only. This module only
  builds bounded, protocol-safe candidate input for the product-owned compactor.
  """

  alias JidoCode.ContextManagement
  alias JidoCode.Conversations.{ChildWork, Turn}

  @summary_text_limit 1_000

  @spec compaction_candidate(map(), map(), keyword() | map()) ::
          {:ok, ContextManagement.compaction_candidate()} | {:error, term()}
  def compaction_candidate(state_or_snapshot, action, opts \\ [])
      when is_map(state_or_snapshot) and is_map(action) do
    ContextManagement.compaction_candidate(
      messages_from_state(state_or_snapshot),
      candidate_attrs(state_or_snapshot, action),
      opts
    )
  end

  @spec messages_from_state(map()) :: [map()]
  def messages_from_state(state_or_snapshot) when is_map(state_or_snapshot) do
    child_work_by_turn = child_work_by_turn_id(state_or_snapshot)

    state_or_snapshot
    |> ordered_turns()
    |> Enum.reject(&ignored_turn?/1)
    |> Enum.map(fn turn -> turn_message(turn, Map.get(child_work_by_turn, turn_id(turn), [])) end)
    |> Enum.reject(&is_nil/1)
  end

  def messages_from_state(_state_or_snapshot), do: []

  @spec context_compacted_event_payload(map()) :: {:ok, map()} | {:error, term()}
  def context_compacted_event_payload(attrs) when is_map(attrs) do
    with :ok <- ContextManagement.reject_raw_context_metadata(attrs),
         {:ok, summary_id} <- required_string(attrs, :summary_id),
         {:ok, source_span_ids} <- required_string_list(attrs, :source_span_ids) do
      {:ok,
       %{
         "summary_id" => summary_id,
         "recommendation_id" => field(attrs, :recommendation_id) |> normalize_optional_string(),
         "debounce_key" => field(attrs, :debounce_key) |> normalize_optional_string(),
         "source_span_ids" => source_span_ids,
         "policy_id" => field(attrs, :policy_id) |> normalize_optional_string(),
         "workflow" => field(attrs, :workflow) |> normalize_optional_string(),
         "specialist_role" => field(attrs, :specialist_role) |> normalize_optional_string(),
         "reset_sequence" => field(attrs, :reset_sequence),
         "state" => "compacted"
       }
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)
       |> Map.new()}
    end
  end

  def context_compacted_event_payload(_attrs), do: {:error, :invalid_context_compacted_event_payload}

  defp candidate_attrs(state_or_snapshot, action) do
    %{
      managed_repo_id: field(action, :managed_repo_id) || field(state_or_snapshot, :managed_repo_id),
      work_item_id: field(action, :work_item_id) || field(state_or_snapshot, :work_item_id),
      workflow: field(action, :workflow),
      specialist_role: field(action, :specialist_role),
      conversation_id: field(action, :conversation_id) || field(state_or_snapshot, :conversation_id),
      turn_id: field(action, :turn_id),
      policy_id: field(action, :policy_id)
    }
  end

  defp ordered_turns(%{turn_order: turn_order, turns: turns}) when is_list(turn_order) and is_map(turns) do
    turn_order
    |> Enum.map(&Map.get(turns, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp ordered_turns(%{"turn_order" => turn_order, "turns" => turns}) when is_list(turn_order) and is_map(turns) do
    turn_order
    |> Enum.map(&Map.get(turns, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp ordered_turns(state_or_snapshot) do
    state_or_snapshot
    |> field(:turns, [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp child_work_by_turn_id(state_or_snapshot) do
    state_or_snapshot
    |> ordered_child_works()
    |> Enum.filter(&(child_work_state(&1) == "completed"))
    |> Enum.group_by(&field(&1, :turn_id))
  end

  defp ordered_child_works(%{child_work_order: child_work_order, child_works: child_works})
       when is_list(child_work_order) and is_map(child_works) do
    child_work_order
    |> Enum.map(&Map.get(child_works, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp ordered_child_works(%{"child_work_order" => child_work_order, "child_works" => child_works})
       when is_list(child_work_order) and is_map(child_works) do
    child_work_order
    |> Enum.map(&Map.get(child_works, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp ordered_child_works(state_or_snapshot) do
    state_or_snapshot
    |> field(:child_works, [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp ignored_turn?(turn) do
    turn_state(turn) in ["cancelled", "superseded", "failed"]
  end

  defp turn_message(turn, child_works) do
    content =
      [
        instruction_text(turn),
        completed_child_work_text(child_works)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> normalize_optional_string()

    if content do
      %{id: "turn:#{turn_id(turn)}", role: "user", content: content}
    end
  end

  defp instruction_text(turn) do
    turn
    |> turn_payload()
    |> then(fn payload ->
      field(payload, :instruction) ||
        field(payload, :intent) ||
        field(payload, :reason) ||
        get_in(payload, ["clarification_resume", "response"]) ||
        field(payload, :summary)
    end)
    |> normalize_optional_string()
    |> case do
      nil -> nil
      instruction -> "Instruction: #{bounded_text(instruction)}"
    end
  end

  defp completed_child_work_text([]), do: nil

  defp completed_child_work_text(child_works) do
    child_works
    |> Enum.map(&child_work_summary/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      summaries -> "Completed result: #{Enum.join(summaries, "\nCompleted result: ")}"
    end
  end

  defp child_work_summary(child_work) do
    child_work
    |> field(:result, %{})
    |> normalize_map()
    |> then(fn result ->
      field(result, :summary) ||
        get_in(result, ["result", "summary"]) ||
        get_in(result, ["latest_progress", "summary"]) ||
        field(result, :text) ||
        field(result, :detail)
    end)
    |> normalize_optional_string()
    |> case do
      nil -> nil
      summary -> bounded_text(summary)
    end
  end

  defp turn_id(%Turn{id: id}), do: id
  defp turn_id(turn), do: field(turn, :id)

  defp turn_payload(%Turn{payload: payload}), do: normalize_map(payload)
  defp turn_payload(turn), do: turn |> field(:payload, %{}) |> normalize_map()

  defp turn_state(%Turn{state: state}), do: normalize_optional_string(state)
  defp turn_state(turn), do: turn |> field(:state) |> normalize_optional_string()

  defp child_work_state(%ChildWork{state: state}), do: normalize_optional_string(state)
  defp child_work_state(child_work), do: child_work |> field(:state) |> normalize_optional_string()

  defp bounded_text(text) do
    text
    |> normalize_optional_string()
    |> case do
      nil -> nil
      normalized -> String.slice(normalized, 0, @summary_text_limit)
    end
  end

  defp field(map, key, default \\ nil)

  defp field(%Turn{} = turn, key, default), do: Map.get(turn, key, default)
  defp field(%ChildWork{} = child_work, key, default), do: Map.get(child_work, key, default)

  defp field(map, key, default) when is_map(map) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp field(_map, _key, default), do: default

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

  defp required_string(attrs, key) do
    case field(attrs, key) |> normalize_optional_string() do
      nil -> {:error, {:missing_required_context_compaction_field, key}}
      value -> {:ok, value}
    end
  end

  defp required_string_list(attrs, key) do
    attrs
    |> field(key, [])
    |> normalize_string_list()
    |> case do
      [] -> {:error, {:missing_required_context_compaction_field, key}}
      values -> {:ok, values}
    end
  end

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_string_list(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> []
      string -> [string]
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value), do: inspect(value)
end
