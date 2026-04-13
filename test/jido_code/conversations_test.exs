defmodule JidoCode.ConversationsTest do
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations
  alias JidoCode.Operations.{Ingress, WorkItem}
  alias JidoCode.Projects.Project

  test "start creates a repo-scoped pre-work conversation with explicit actor attribution" do
    managed_repo = managed_repo_fixture!("conversation-repo-scoped")

    assert {:ok, %{conversation: conversation, work_item: nil, work_action: nil}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               title: "Investigate failing tests",
               objective: "Investigate failing tests in the managed repository.",
               actor: %{id: "operator-conversation", email: "conversation@example.com"},
               source_metadata: %{entry_surface: "chat"},
               conversation_metadata: %{
                 correlation_id: "corr-repo-scoped",
                 requested_by: "chat"
               }
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == nil
    assert conversation.scope == :repo_scoped
    assert conversation.attachment_mode == :pre_work
    assert conversation.source == "conversation"
    assert conversation.title == "Investigate failing tests"
    assert conversation.initiating_actor["id"] == "operator-conversation"
    assert conversation.initiating_actor["actor_class"] == "operator"
    assert conversation.source_metadata["entry_surface"] == "chat"
    assert conversation.conversation_metadata["correlation_id"] == "corr-repo-scoped"
    assert conversation.conversation_metadata["requested_by"] == "chat"
  end

  test "start can attach to an existing work item without creating another work item" do
    managed_repo = managed_repo_fixture!("conversation-existing-work")
    work_item = work_item_fixture!(managed_repo, "operator-existing-work")

    assert {:ok, %{conversation: conversation, work_item: attached_work_item, work_action: nil}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               work_item_id: work_item.id,
               source: "conversation",
               objective: "Continue the existing governed work item."
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id
    assert conversation.scope == :work_item_scoped
    assert conversation.attachment_mode == :existing_work_item
    assert attached_work_item.id == work_item.id

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(query: [filter: [id: work_item.id]], actor: Actor.operator_actor())

    assert persisted_work_item.id == work_item.id
  end

  test "start can synthesize and attach a new work item when requested" do
    managed_repo = managed_repo_fixture!("conversation-synthesized-work")

    assert {:ok, %{conversation: conversation, work_item: work_item, work_action: :created}} =
             Conversations.start(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               attach_mode: :synthesized_work_item,
               objective: "Review the operator request before execution.",
               actor: %{id: "operator-synth", email: "synth@example.com"}
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id
    assert conversation.scope == :work_item_scoped
    assert conversation.attachment_mode == :synthesized_work_item
    assert work_item.managed_repo_id == managed_repo.id
    assert work_item.recommended_action == "review_operator_request"
    assert work_item.initiating_actor["id"] == "operator-synth"
  end

  test "resume preserves conversation scope and refreshes last activity" do
    managed_repo = managed_repo_fixture!("conversation-resume")

    {:ok, %{conversation: conversation}} =
      Conversations.start(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Resume the coding session."
      })

    assert {:ok, resumed} = Conversations.resume(conversation.id, actor: Actor.operator_actor())

    assert resumed.id == conversation.id
    assert resumed.managed_repo_id == managed_repo.id
    assert resumed.scope == :repo_scoped
    assert DateTime.compare(resumed.last_activity_at, conversation.last_activity_at) in [:gt, :eq]
  end

  test "latest_for_managed_repo returns the most recently active conversation" do
    managed_repo = managed_repo_fixture!("conversation-latest")

    {:ok, %{conversation: first_conversation}} =
      Conversations.start(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Start the earlier conversation."
      })

    {:ok, %{conversation: second_conversation}} =
      Conversations.start(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Start the later conversation."
      })

    assert {:ok, latest_conversation} =
             Conversations.latest_for_managed_repo(managed_repo.id, actor: Actor.operator_actor())

    assert latest_conversation.id == second_conversation.id

    assert {:ok, refreshed_first_conversation} =
             Conversations.resume(first_conversation.id, actor: Actor.operator_actor())

    assert {:ok, latest_after_resume} =
             Conversations.latest_for_managed_repo(managed_repo.id, actor: Actor.operator_actor())

    assert latest_after_resume.id == refreshed_first_conversation.id
  end

  test "steer_work can keep a conversation repo-scoped while recording bounded steering context" do
    managed_repo = managed_repo_fixture!("conversation-steer-pre-work")

    {:ok, %{conversation: conversation}} =
      Conversations.start(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Inspect the repository before committing to governed work."
      })

    assert {:ok, %{conversation: updated_conversation, work_item: nil, work_action: nil}} =
             Conversations.steer_work(
               conversation,
               %{instruction: "Narrow the repo-scoped objective before creating work."},
               actor: Actor.operator_actor(%{"id" => "operator-pre-work"}),
               shared_context: %{
                 referenced_files: ["lib/jido_code/conversations.ex"],
                 accepted_tool_results: [%{"child_work_id" => "tool-1"}]
               }
             )

    assert updated_conversation.id == conversation.id
    assert updated_conversation.managed_repo_id == managed_repo.id
    assert updated_conversation.work_item_id == nil
    assert updated_conversation.scope == :repo_scoped
    assert updated_conversation.attachment_mode == :pre_work
    assert updated_conversation.conversation_metadata["canonical_work_surface"] == "work_item"
    assert updated_conversation.conversation_metadata["shared_context_contract"] == "bounded"
    assert updated_conversation.conversation_metadata["last_steer_command"] == "turn.steer"

    assert updated_conversation.conversation_metadata["shared_context_summary"] == %{
             "referenced_file_count" => 1,
             "accepted_tool_result_count" => 1,
             "pending_clarification" => false
           }

    assert List.last(updated_conversation.conversation_metadata["steering_history"]) == %{
             "attachment_mode" => "pre_work",
             "command" => "turn.steer",
             "instruction" => "Narrow the repo-scoped objective before creating work.",
             "scope" => "repo_scoped",
             "work_item_id" => nil,
             "at" => updated_conversation.conversation_metadata["last_steered_at"]
           }
  end

  test "steer_work can attach repo-scoped conversations to existing governed work" do
    managed_repo = managed_repo_fixture!("conversation-steer-existing-work")
    work_item = work_item_fixture!(managed_repo, "operator-existing-steer")

    {:ok, %{conversation: conversation}} =
      Conversations.start(%{
        managed_repo_id: managed_repo.id,
        source: "conversation",
        objective: "Start repo-scoped before steering to governed work."
      })

    assert {:ok,
            %{
              conversation: updated_conversation,
              work_item: steered_work_item,
              work_action: :steered
            }} =
             Conversations.steer_work(
               conversation,
               %{
                 work_item_id: work_item.id,
                 instruction: "Redirect the conversation onto the governed work item."
               },
               actor: Actor.operator_actor(%{"id" => "operator-steer-existing"}),
               shared_context: %{
                 referenced_files: [
                   "lib/jido_code/conversations.ex",
                   "lib/jido_code/agent_workspace.ex"
                 ],
                 accepted_tool_results: [%{"child_work_id" => "tool-2"}]
               }
             )

    assert updated_conversation.id == conversation.id
    assert updated_conversation.managed_repo_id == managed_repo.id
    assert updated_conversation.work_item_id == work_item.id
    assert updated_conversation.scope == :work_item_scoped
    assert updated_conversation.attachment_mode == :existing_work_item
    assert steered_work_item.id == work_item.id
    assert steered_work_item.managed_repo_id == managed_repo.id

    assert updated_conversation.conversation_metadata["active_work_item_id"] == work_item.id
    assert updated_conversation.conversation_metadata["last_work_action"] == "steered"

    assert updated_conversation.conversation_metadata["shared_context_summary"] == %{
             "referenced_file_count" => 2,
             "accepted_tool_result_count" => 1,
             "pending_clarification" => false
           }

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(query: [filter: [id: work_item.id], limit: 1], actor: Actor.operator_actor())

    assert persisted_work_item.initiating_actor["id"] == "operator-steer-existing"
    assert List.last(persisted_work_item.audit_log)["action"] == "steered"
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "conversation-#{suffix}",
        github_full_name: "owner/conversation-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end

  defp work_item_fixture!(managed_repo, actor_id) do
    {:ok, %{work_item: work_item}} =
      Ingress.record_operator_intake(%{
        managed_repo_id: managed_repo.id,
        channel: "workbench",
        intent: "fix_workflow_kickoff",
        actor: %{id: actor_id, email: "#{actor_id}@example.com"},
        payload: %{
          "workflow_name" => "fix_failing_tests",
          "context_item" => %{"type" => "issue"}
        },
        source_metadata: %{
          "trigger" => %{"source" => "workbench", "mode" => "manual"}
        }
      })

    work_item
  end
end
