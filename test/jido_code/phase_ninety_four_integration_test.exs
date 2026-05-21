defmodule JidoCode.PhaseNinetyFourIntegrationTest do
  # covers: architecture.context_management_pod.context_lifecycle_is_observable
  # covers: architecture.context_compaction_policy.compaction_preserves_required_context
  # covers: architecture.context_compaction_policy.compaction_summaries_are_prompt_context_not_memory
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations
  alias JidoCode.Conversations.{ChildWork, Conversation, Event, Persistence, Snapshot, Turn}
  alias JidoCode.Projects.Project

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

  test "reset events survive persistence and cold restore" do
    managed_repo = managed_repo_fixture!("phase-94-reset-restore")

    assert {:ok, %{conversation: conversation}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               source: "project_detail",
               attach_mode: :synthesized_work_item,
               objective: "Restore reset-aware context."
             })

    state = conversation_state_with_reset(conversation)
    previous_state = %{state | events: [], event_sequence: 0}

    assert :ok = Persistence.persist_transition(previous_state, state)
    assert {:ok, restored_state} = Persistence.restore_state(conversation)

    restored_snapshot = Snapshot.from_state(restored_state)
    assert Enum.any?(restored_snapshot.events, &(&1.name == "conversation.context_compacted"))
    assert restored_snapshot.shared_context["latest_context_reset"]["summary_id"] == "summary-94"
    refute "lib/old.ex" in restored_snapshot.shared_context["referenced_files"]
    assert "lib/new.ex" in restored_snapshot.shared_context["referenced_files"]
  end

  defp conversation_state_with_reset(conversation \\ nil) do
    conversation = conversation || conversation_struct()
    conversation_id = conversation.id

    turn_1 = turn(conversation_id, "turn-1", "older request", ["lib/old.ex"])
    turn_2 = turn(conversation_id, "turn-2", "active request", ["lib/new.ex"])
    child_1 = child_work(conversation, "child-1", "turn-1", "older result", ["lib/old_result.ex"])
    child_2 = child_work(conversation, "child-2", "turn-2", "new result", ["lib/new_result.ex"])

    %{
      conversation: conversation,
      status: conversation.status,
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
        Event.new(conversation_id, 1, "conversation.message_added", %{
          payload: %{"payload" => %{"instruction" => "older request"}}
        }),
        Event.new(conversation_id, 2, "conversation.context_compacted", %{
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

  defp conversation_struct do
    %Conversation{
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
  end

  defp turn(conversation_id, id, instruction, referenced_files) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Turn{
      id: id,
      conversation_id: conversation_id,
      command_id: "command-#{id}",
      command_type: "turn.submit",
      state: :completed,
      payload: %{"instruction" => instruction, "referenced_files" => referenced_files},
      inserted_at: now,
      completed_at: now
    }
  end

  defp child_work(conversation, id, turn_id, summary, referenced_files) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %ChildWork{
      id: id,
      conversation_id: conversation.id,
      managed_repo_id: conversation.managed_repo_id,
      work_item_id: conversation.work_item_id,
      turn_id: turn_id,
      tool_call_id: "tool-#{id}",
      kind: "tool_call",
      state: :completed,
      inserted_at: now,
      completed_at: now,
      result: %{"summary" => summary, "referenced_files" => referenced_files}
    }
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-ninety-four-#{suffix}",
        github_full_name: "owner/phase-ninety-four-#{suffix}",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => Path.join(System.tmp_dir!(), "phase-ninety-four-#{suffix}"),
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} = ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())
    managed_repo
  end
end
