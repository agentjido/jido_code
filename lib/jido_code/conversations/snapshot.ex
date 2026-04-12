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
      events: []
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
      events: Enum.map(state.events, &Event.summary/1)
    }
  end

  defp summarize_turn(nil), do: nil

  defp summarize_turn(%Turn{} = turn) do
    %{
      id: turn.id,
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
end
