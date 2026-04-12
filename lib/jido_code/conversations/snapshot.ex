defmodule JidoCode.Conversations.Snapshot do
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  @moduledoc """
  Materialized conversation snapshot shaping for delivery and reconnect recovery.
  """

  alias JidoCode.Conversations.{ChildWork, Conversation, Event, Turn}

  @spec empty(Conversation.t()) :: map()
  def empty(%Conversation{} = conversation) do
    %{
      conversation_id: conversation.id,
      managed_repo_id: conversation.managed_repo_id,
      work_item_id: conversation.work_item_id,
      status: conversation.status,
      admission_paused: conversation.status == :paused,
      child_execution_paused: false,
      active_turn_id: nil,
      active_turn: nil,
      active_child_work_id: nil,
      active_child_work: nil,
      queued_turn_ids: [],
      turns: [],
      child_works: [],
      control_history: [],
      last_event_sequence: 0,
      event_count: 0,
      events: [],
      shared_context: shared_context_for_conversation(conversation)
    }
  end

  @spec from_state(map()) :: map()
  def from_state(state) when is_map(state) do
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
      control_history: state.control_history,
      last_event_sequence: state.event_sequence,
      event_count: length(state.events),
      events: Enum.map(state.events, &Event.summary/1),
      shared_context: shared_context_from_state(state)
    }
  end

  @spec restore_state(Conversation.t(), map(), [map()]) :: map()
  def restore_state(%Conversation{} = conversation, snapshot, event_summaries \\ [])
      when is_map(snapshot) and is_list(event_summaries) do
    turns =
      snapshot
      |> map_get(:turns, [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Turn.from_summary/1)

    child_works =
      snapshot
      |> map_get(:child_works, [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(&ChildWork.from_summary/1)

    restored_events =
      case event_summaries do
        [] ->
          snapshot
          |> map_get(:events, [])
          |> Enum.filter(&is_map/1)
          |> Enum.map(&Event.from_summary/1)

        _events ->
          Enum.map(event_summaries, &Event.from_summary/1)
      end

    status = normalize_status(map_get(snapshot, :status, conversation.status))
    turns_by_id = Map.new(turns, &{&1.id, &1})
    child_works_by_id = Map.new(child_works, &{&1.id, &1})
    active_turn_id = restore_active_turn_id(snapshot, turns_by_id)

    %{
      conversation: %{
        conversation
        | status: status,
          work_item_id: normalize_optional_string(map_get(snapshot, :work_item_id)) || conversation.work_item_id
      },
      status: status,
      admission_paused: normalize_boolean(map_get(snapshot, :admission_paused, status == :paused)),
      child_execution_paused: normalize_boolean(map_get(snapshot, :child_execution_paused, false)),
      active_turn_id: active_turn_id,
      work_queue: normalize_string_list(map_get(snapshot, :queued_turn_ids, [])),
      turns: turns_by_id,
      turn_order: Enum.map(turns, & &1.id),
      control_history: normalize_map_list(map_get(snapshot, :control_history, [])),
      child_works: child_works_by_id,
      child_work_order: Enum.map(child_works, & &1.id),
      child_worker_pids: %{},
      event_sequence: max_event_sequence(snapshot, restored_events),
      events: restored_events
    }
  end

  defp summarize_turn(nil), do: nil

  defp summarize_turn(%Turn{} = turn) do
    %{
      id: turn.id,
      conversation_id: turn.conversation_id,
      command_id: turn.command_id,
      command_type: turn.command_type,
      actor: turn.actor,
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
      actor: child_work.actor,
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

  defp shared_context_for_conversation(%Conversation{} = conversation) do
    %{
      "managed_repo_id" => conversation.managed_repo_id,
      "work_item_id" => conversation.work_item_id,
      "referenced_files" => [],
      "accepted_tool_results" => []
    }
  end

  defp shared_context_from_state(state) do
    turns =
      state.turn_order
      |> Enum.map(&Map.fetch!(state.turns, &1))

    %{}
    |> Map.put("managed_repo_id", state.conversation.managed_repo_id)
    |> Map.put("work_item_id", state.conversation.work_item_id)
    |> Map.put("referenced_files", referenced_files(turns, state))
    |> Map.put("accepted_tool_results", accepted_tool_results(state))
    |> maybe_put("latest_turn_id", latest_turn_id(turns))
    |> maybe_put("latest_instruction", latest_instruction(turns))
    |> maybe_put("pending_clarification", pending_clarification(turns))
  end

  defp referenced_files(turns, state) do
    accepted_result_files =
      state
      |> accepted_tool_results()
      |> Enum.flat_map(fn result ->
        result
        |> Map.get("result", %{})
        |> referenced_files_from_map()
      end)

    turns
    |> Enum.reject(&(&1.state in [:superseded, :cancelled, :failed]))
    |> Enum.flat_map(fn turn -> referenced_files_from_map(turn.payload) end)
    |> Kernel.++(accepted_result_files)
    |> Enum.uniq()
    |> Enum.take(-12)
  end

  defp accepted_tool_results(state) do
    state.child_work_order
    |> Enum.map(&Map.fetch!(state.child_works, &1))
    |> Enum.filter(fn child_work ->
      case Map.get(state.turns, child_work.turn_id) do
        %Turn{state: turn_state} ->
          child_work.state == :completed and turn_state in [:running, :awaiting_input, :completed]

        _other ->
          false
      end
    end)
    |> Enum.map(fn child_work ->
      %{
        "child_work_id" => child_work.id,
        "turn_id" => child_work.turn_id,
        "tool_call_id" => child_work.tool_call_id,
        "kind" => child_work.kind,
        "completed_at" => child_work.completed_at,
        "result" => child_work.result || %{}
      }
    end)
    |> Enum.take(-5)
  end

  defp latest_turn_id(turns) do
    turns
    |> Enum.reverse()
    |> Enum.find_value(fn turn ->
      if turn.command_type in ["turn.submit", "turn.steer"], do: turn.id, else: nil
    end)
  end

  defp latest_instruction(turns) do
    turns
    |> Enum.reverse()
    |> Enum.find_value(fn turn ->
      instruction =
        Map.get(turn.payload, "instruction") ||
          Map.get(turn.payload, "intent") ||
          Map.get(turn.payload, "reason")

      normalize_optional_string(instruction)
    end)
  end

  defp pending_clarification(turns) do
    case Enum.find(Enum.reverse(turns), &(&1.state == :awaiting_input)) do
      %Turn{} = turn ->
        %{
          "turn_id" => turn.id,
          "command_type" => turn.command_type,
          "payload" => turn.payload
        }

      _other ->
        nil
    end
  end

  defp referenced_files_from_map(value) when is_map(value) do
    []
    |> Kernel.++(normalize_string_list(Map.get(value, "referenced_files")))
    |> Kernel.++(normalize_string_list(Map.get(value, "files")))
    |> Kernel.++(List.wrap(normalize_optional_string(Map.get(value, "file"))))
    |> Kernel.++(List.wrap(normalize_optional_string(Map.get(value, "path"))))
  end

  defp referenced_files_from_map(_value), do: []

  defp map_get(map, key, default \\ nil) when is_map(map) do
    string_key =
      case key do
        atom when is_atom(atom) -> Atom.to_string(atom)
        binary when is_binary(binary) -> binary
      end

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp restore_active_turn_id(snapshot, turns_by_id) do
    case normalize_optional_string(map_get(snapshot, :active_turn_id)) do
      nil ->
        nil

      active_turn_id ->
        case Map.get(turns_by_id, active_turn_id) do
          %Turn{state: :awaiting_input} -> active_turn_id
          _other -> nil
        end
    end
  end

  defp max_event_sequence(snapshot, restored_events) do
    max(
      normalize_non_negative_integer(map_get(snapshot, :last_event_sequence, 0)),
      restored_events
      |> Enum.map(& &1.sequence)
      |> Enum.max(fn -> 0 end)
    )
  end

  defp normalize_status(status) when status in [:active, :paused, :completed, :cancelled], do: status

  defp normalize_status(status) when is_binary(status) do
    case status do
      "active" -> :active
      "paused" -> :paused
      "completed" -> :completed
      "cancelled" -> :cancelled
      _other -> :active
    end
  end

  defp normalize_status(_status), do: :active

  defp normalize_boolean(value) when is_boolean(value), do: value
  defp normalize_boolean(value) when value in ["true", "1"], do: true
  defp normalize_boolean(_value), do: false

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_value), do: []

  defp normalize_map_list(value) when is_list(value), do: Enum.filter(value, &is_map/1)
  defp normalize_map_list(_value), do: []

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> 0
    end
  end

  defp normalize_non_negative_integer(_value), do: 0

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
