defmodule JidoCode.Conversations.PolicyTest do
  # covers: architecture.policy_layers.policy_layers_interlock_without_collapsing
  # covers: architecture.policy_layers.repository_governance_policy_is_repo_control_layer
  # covers: architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
  use JidoCode.DataCase, async: false

  alias JidoCode.Conversations.{Ingress, Policy}
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.PolicySet
  alias JidoCode.Projects.Project

  test "repo governance can prefer steering existing work for auto-post conversations" do
    {:ok, project} = create_project("repo-conversation-policy-auto-post")

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, _policy_set} =
             PolicySet.upsert_default_for_managed_repo(
               %{
                 managed_repo_id: managed_repo.id,
                 review_policy: %{
                   mode: "auto_post",
                   requires_human_approval: false,
                   change_request_required: false,
                   review_threshold: "auto_post",
                   required_stage: "approval",
                   source: "policy_test_override"
                 }
               },
               actor: Actor.admin_actor()
             )

    assert {:ok, %{work_item: existing_work_item}} =
             Ingress.record_turn(%{
               actor_id: "operator-policy",
               actor_email: "policy@example.com",
               project_id: project.id,
               conversation_id: "conversation-policy-seed",
               content: "Create initial work for the repository."
             })

    assert {:ok, decision} =
             Policy.decide(%{
               project_id: project.id
             })

    assert decision.action == :steer_existing_work
    assert decision.work_item_id == existing_work_item.id
    assert decision.reason_code == "repo_policy_prefers_steering"
    assert decision.review_policy["mode"] == "auto_post"
  end

  test "missing explicit steering target halts before runtime execution begins" do
    {:ok, project} = create_project("repo-conversation-policy-halt")

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:error, :target_work_item_not_found, decision} =
             Policy.decide(%{
               managed_repo_id: managed_repo.id,
               work_item_id: Ecto.UUID.generate()
             })

    assert decision.action == :halt
    assert decision.reason_code == "target_work_item_not_found"
  end

  defp create_project(name) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
      default_branch: "main",
      settings: %{}
    })
  end
end
