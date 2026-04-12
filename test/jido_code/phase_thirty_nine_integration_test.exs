defmodule JidoCode.PhaseThirtyNineIntegrationTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.Operations.{Ingress, WorkItem}
  alias JidoCode.Projects.Project

  test "repo-scoped conversations preserve managed-repo scope and operator attribution through the driver" do
    managed_repo = managed_repo_fixture!("repo-scoped")

    assert {:ok, %{conversation: conversation, snapshot: snapshot, work_item: nil}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               title: "Investigate conversation entrypoint behavior",
               objective: "Validate repo-scoped conversation setup.",
               actor: %{id: "operator-phase39", email: "phase39@example.com"},
               source_metadata: %{entry_surface: "chat"}
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.scope == :repo_scoped
    assert conversation.attachment_mode == :pre_work
    assert conversation.initiating_actor["id"] == "operator-phase39"
    assert conversation.source_metadata["entry_surface"] == "chat"

    assert snapshot.conversation_id == conversation.id
    assert snapshot.managed_repo_id == managed_repo.id
    refute Map.has_key?(snapshot, :kernel_name)
    refute Map.has_key?(snapshot, :pod_id)

    assert :ok = Driver.stop(conversation.id)
  end

  test "work-item scoped conversations can attach to an existing governed work item without spawning a duplicate" do
    managed_repo = managed_repo_fixture!("existing-work")
    work_item = work_item_fixture!(managed_repo, "operator-existing")

    assert {:ok, %{conversation: conversation, work_item: attached_work_item, snapshot: snapshot}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               work_item_id: work_item.id,
               source: "conversation",
               objective: "Continue the existing governed work item.",
               actor: %{id: "operator-existing", email: "existing@example.com"}
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id
    assert conversation.scope == :work_item_scoped
    assert conversation.attachment_mode == :existing_work_item
    assert attached_work_item.id == work_item.id
    assert snapshot.work_item_id == work_item.id

    assert {:ok, work_items} =
             WorkItem.read(
               query: [filter: [managed_repo_id: managed_repo.id]],
               actor: Actor.operator_actor()
             )

    assert Enum.map(work_items, & &1.id) == [work_item.id]

    assert :ok = Driver.stop(conversation.id)
  end

  test "actionable conversations can synthesize new governed work when asked to do so" do
    managed_repo = managed_repo_fixture!("synthesized-work")

    assert {:ok, %{conversation: conversation, work_item: work_item, snapshot: snapshot}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               attach_mode: :synthesized_work_item,
               objective: "Review the operator request before execution.",
               actor: %{id: "operator-synthesized", email: "synthesized@example.com"}
             })

    assert conversation.managed_repo_id == managed_repo.id
    assert conversation.work_item_id == work_item.id
    assert conversation.scope == :work_item_scoped
    assert conversation.attachment_mode == :synthesized_work_item
    assert snapshot.work_item_id == work_item.id
    assert work_item.managed_repo_id == managed_repo.id
    assert work_item.recommended_action == "review_operator_request"

    assert :ok = Driver.stop(conversation.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-thirty-nine-#{suffix}",
        github_full_name: "owner/phase-thirty-nine-#{suffix}",
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
