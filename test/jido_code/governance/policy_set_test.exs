defmodule JidoCode.Governance.PolicySetTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo, SourceRepo}
  alias JidoCode.Governance.PolicySet
  alias JidoCode.Projects.Project

  test "project create seeds the default policy set from transitional approval configuration" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"approval_mode" => "auto_post"}
          }
        }
      })

    {:ok, managed_repo} = ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())
    {:ok, policy_set} = PolicySet.get_by_managed_repo_name(managed_repo.id, "default", actor: Actor.operator_actor())

    assert policy_set.review_policy.mode == "auto_post"
    assert policy_set.review_policy.requires_human_approval == false
    assert policy_set.review_policy.source == "support_agent_config.github_issue_bot.approval_mode"
  end

  test "control-plane mutations require explicit actor classes" do
    attrs = %{
      provider: :github,
      owner: "owner",
      name: "repo-one",
      full_name: "owner/repo-one",
      default_branch: "main"
    }

    assert {:error, %Ash.Error.Forbidden{}} = SourceRepo.upsert_identity(attrs)

    assert {:error, %Ash.Error.Forbidden{}} =
             SourceRepo.upsert_identity(attrs, actor: Actor.external_ingress_actor())

    assert {:ok, source_repo} =
             SourceRepo.upsert_identity(attrs, actor: Actor.managed_repo_orchestrator_actor())

    assert source_repo.full_name == "owner/repo-one"
  end

  test "policy set writes are available to admin-class actors and denied to external ingress" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} = ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:error, %Ash.Error.Forbidden{}} =
             PolicySet.upsert_default_for_managed_repo(
               %{
                 managed_repo_id: managed_repo.id,
                 review_policy: %{
                   mode: "auto_post",
                   requires_human_approval: false,
                   source: "manual_override"
                 }
               },
               actor: Actor.external_ingress_actor()
             )

    assert {:ok, policy_set} =
             PolicySet.upsert_default_for_managed_repo(
               %{
                 managed_repo_id: managed_repo.id,
                 review_policy: %{
                   mode: "auto_post",
                   requires_human_approval: false,
                   source: "manual_override"
                 }
               },
               actor: Actor.admin_actor()
             )

    assert policy_set.review_policy.mode == "auto_post"
    assert policy_set.review_policy.source == "manual_override"
  end
end
