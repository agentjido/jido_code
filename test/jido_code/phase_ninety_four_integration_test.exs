defmodule JidoCode.PhaseNinetyFourIntegrationTest do
  # covers: architecture.context_management_pod.context_lifecycle_is_observable
  # covers: architecture.context_compaction_policy.compaction_preserves_required_context
  # covers: architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory
  use ExUnit.Case, async: true

  alias JidoCode.Conversations.{ChildWork, Conversation, Event, Snapshot, Turn}

  test "context reset filters prompt-facing shared context without removing history" do
    state = conversation_state_with_reset()

    snapshot = Snapshot.from_state(state)

    assert length(snapshot.events) == 2
    assert Enum.any?(snapshot.events, &(&1.name == "conversation.message_added"))
    assert Enum.any?(snapshot.events, &(&1.name == "conversation.context_compacted"))

    shared_context = snapshot.shared_context
    assert shared_context["latest_context_reset"]["summary_id"] == "summary-94"
    assert shared_context["active_compaction_summary_ids"] == ["summary-94"]

    refute "lib/old.ex" in shared_context["referenced_files"]
    refute "lib/old_result.ex" in shared_context["referenced_files"]
    assert "lib/new.ex" in shared_context["referenced_files"]
    assert "lib/new_result.ex" in shared_context["referenced_files"]

    assert [%{"child_work_id" => "child-2"}] = shared_context["accepted_tool_results"]
    assert shared_context["latest_instruction"] == "active request"
  end

  defp conversation_state_with_reset do
    conversation = %Conversation{
      id: "conversation-94",
      managed_repo_id: "repo-94",
      work_item_id: "work-94",
      status: :active,
      scope: :work_item_scoped,
      attachment_mode: :existing_work_item,
      source: "project_detail",
      objective: "Keep context bounded.",
      conversation_metadata: %{},
      source_metadata: %{}
    }

    turn_1 = turn("turn-1", "older request", ["lib/old.ex"])
    turn_2 = turn("turn-2", "active request", ["lib/new.ex"])
    child_1 = child_work("child-1", "turn-1", "older result", ["lib/old_result.ex"])
    child_2 = child_work("child-2", "turn-2", "new result", ["lib/new_result.ex"])

    %{
      conversation: conversation,
      status: :active,
      admission_paused: false,
      child_execution_paused: false,
      active_turn_id: nil,
      work_queue: [],
      turns: %{"turn-1" => turn_1, "turn-2" => turn_2},
      turn_order: ["turn-1", "turn-2"],
      control_history: [],
      child_works: %{"child-1" => child_1, "child-2" => child_2},
      child_work_order: ["child-1", "child-2"],
      child_worker_pids: %{},
      event_sequence: 2,
      events: [
        Event.new("conversation-94", 1, "conversation.message_added", %{
          payload: %{"payload" => %{"instruction" => "older request"}}
        }),
        Event.new("conversation-94", 2, "conversation.context_compacted", %{
          payload: %{
            "summary_id" => "summary-94",
            "recommendation_id" => "recommendation-94",
            "source_span_ids" => ["turn:turn-1"],
            "policy_id" => "context-management:v1",
            "workflow" => "execute",
            "specialist_role" => "coder",
            "reset_sequence" => 2
          }
        })
      ]
    }
  end

  defp turn(id, instruction, referenced_files) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Turn{
      id: id,
      conversation_id: "conversation-94",
      command_id: "command-#{id}",
      command_type: "turn.submit",
      state: :completed,
      payload: %{"instruction" => instruction, "referenced_files" => referenced_files},
      inserted_at: now,
      completed_at: now
    }
  end

  defp child_work(id, turn_id, summary, referenced_files) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %ChildWork{
      id: id,
      conversation_id: "conversation-94",
      managed_repo_id: "repo-94",
      work_item_id: "work-94",
      turn_id: turn_id,
      tool_call_id: "tool-#{id}",
      kind: "tool_call",
      state: :completed,
      inserted_at: now,
      completed_at: now,
      result: %{"summary" => summary, "referenced_files" => referenced_files}
    }
  end
end
