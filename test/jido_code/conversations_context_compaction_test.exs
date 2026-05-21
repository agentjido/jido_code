defmodule JidoCode.Conversations.ContextCompactionTest do
  # covers: architecture.context_compaction_policy.compaction_preserves_required_context
  # covers: architecture.context_compaction_policy.tool_protocol_boundaries_are_preserved
  use ExUnit.Case, async: true

  alias JidoCode.Conversations.ContextCompaction
  alias JidoCode.Conversations.Event

  test "context compacted event payload is canonical and metadata-safe" do
    assert "conversation.context_compacted" in Event.canonical_event_names()

    assert {:ok, payload} =
             ContextCompaction.context_compacted_event_payload(%{
               summary_id: "summary-93",
               recommendation_id: "recommendation-93",
               debounce_key: "debounce-93",
               source_span_ids: ["turn:turn-1"],
               policy_id: "context-management:v1",
               workflow: :execute,
               specialist_role: :coder,
               reset_sequence: 12
             })

    assert payload["summary_id"] == "summary-93"
    assert payload["source_span_ids"] == ["turn:turn-1"]
    assert payload["workflow"] == "execute"
    assert payload["state"] == "compacted"

    assert {:error, :raw_context_metadata_rejected} =
             ContextCompaction.context_compacted_event_payload(%{
               summary_id: "summary-93",
               source_span_ids: ["turn:turn-1"],
               raw_prompt: "do not persist this"
             })
  end

  test "builds a protocol-safe candidate from older completed conversation turns" do
    snapshot = %{
      conversation_id: "conversation-93",
      managed_repo_id: "repo-93",
      work_item_id: "work-93",
      turns: [
        %{
          id: "turn-1",
          state: "completed",
          payload: %{"instruction" => "older implementation request"}
        },
        %{
          id: "turn-2",
          state: "completed",
          payload: %{"instruction" => "active follow-up request"}
        }
      ],
      child_works: [
        %{
          id: "child-1",
          turn_id: "turn-1",
          state: "completed",
          result: %{"summary" => "older implementation finished"}
        },
        %{
          id: "child-2",
          turn_id: "turn-2",
          state: "completed",
          result: %{"summary" => "active follow-up finished"}
        }
      ]
    }

    action = %{
      "state" => "compact",
      "managed_repo_id" => "repo-93",
      "work_item_id" => "work-93",
      "workflow" => "execute",
      "specialist_role" => "coder",
      "conversation_id" => "conversation-93",
      "turn_id" => "turn-2",
      "policy_id" => "context-management:v1"
    }

    assert [%{id: "turn:turn-1"}, %{id: "turn:turn-2"}] =
             ContextCompaction.messages_from_state(snapshot)

    assert {:ok, candidate} = ContextCompaction.compaction_candidate(snapshot, action)

    assert candidate.eligible?
    assert candidate.source_span_ids == ["turn:turn-1"]
    assert candidate.source_text =~ "older implementation request"
    assert candidate.source_text =~ "older implementation finished"
    refute candidate.source_text =~ "active follow-up request"
  end

  test "ignores cancelled failed and superseded turns when building candidates" do
    snapshot = %{
      conversation_id: "conversation-93",
      managed_repo_id: "repo-93",
      work_item_id: "work-93",
      turns: [
        %{id: "turn-cancelled", state: "cancelled", payload: %{"instruction" => "cancelled request"}},
        %{id: "turn-failed", state: "failed", payload: %{"instruction" => "failed request"}},
        %{id: "turn-1", state: "completed", payload: %{"instruction" => "eligible older request"}},
        %{id: "turn-2", state: "running", payload: %{"instruction" => "active request"}}
      ],
      child_works: [
        %{id: "child-1", turn_id: "turn-1", state: "completed", result: %{"summary" => "eligible result"}}
      ]
    }

    action = %{
      "managed_repo_id" => "repo-93",
      "work_item_id" => "work-93",
      "workflow" => "review",
      "specialist_role" => "reviewer",
      "conversation_id" => "conversation-93",
      "turn_id" => "turn-2"
    }

    assert {:ok, candidate} = ContextCompaction.compaction_candidate(snapshot, action)

    assert candidate.source_span_ids == ["turn:turn-1"]
    refute candidate.source_text =~ "cancelled request"
    refute candidate.source_text =~ "failed request"
    refute candidate.source_text =~ "active request"
  end

  test "marks active-only conversation context as ineligible for compaction" do
    snapshot = %{
      conversation_id: "conversation-93",
      managed_repo_id: "repo-93",
      work_item_id: "work-93",
      turns: [
        %{id: "turn-active", state: "running", payload: %{"instruction" => "active request"}}
      ],
      child_works: []
    }

    action = %{
      "managed_repo_id" => "repo-93",
      "work_item_id" => "work-93",
      "workflow" => "execute",
      "specialist_role" => "coder",
      "conversation_id" => "conversation-93",
      "turn_id" => "turn-active"
    }

    assert {:ok, candidate} = ContextCompaction.compaction_candidate(snapshot, action)

    refute candidate.eligible?
    assert candidate.diagnostics.reason == :no_eligible_history
    assert candidate.source_span_ids == []
  end
end
