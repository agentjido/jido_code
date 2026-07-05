defmodule JidoCode.Governance.PolicySetTest do
  # covers: architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
  # covers: architecture.policy_layers.operator_surfaces_propagate_current_actor_for_repo_mutations
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepoStore, SourceRepo}
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Governance.RecordStore, as: GovernanceStore
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.IssueTriageWorkflowKickoff

  setup do
    setup_product_store()
  end

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

    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)
    {:ok, policy_set} = GovernanceStore.get_policy_set_by_managed_repo_name(managed_repo.id, "default")

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

    Actor.clear_policy_actor()

    assert {:error, %{type: :forbidden}} = SourceRepo.upsert_identity(attrs)

    assert {:error, %{type: :forbidden}} =
             SourceRepo.upsert_identity(attrs, actor: Actor.external_ingress_actor())

    assert {:ok, source_repo} =
             SourceRepo.upsert_identity(attrs, actor: Actor.managed_repo_orchestrator_actor())

    assert source_repo.full_name == "owner/repo-one"
  end

  test "policy set writes are store backed and visible to review policy readers" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)

    assert {:ok, policy_set} =
             GovernanceStore.upsert_policy_set(%{
               managed_repo_id: managed_repo.id,
               name: "default",
               review_policy: %{
                 mode: "auto_post",
                 requires_human_approval: false,
                 source: "manual_override"
               }
             })

    assert policy_set.review_policy.mode == "auto_post"
    assert policy_set.review_policy.source == "manual_override"
  end

  test "issue triage policy state prefers autonomous managed repo policy over stale project settings" do
    {:ok, project} =
      Project.create(%{
        name: "repo-policy-override",
        github_full_name: "owner/repo-policy-override",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"approval_mode" => "approval_required"}
          }
        }
      })

    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)

    {:ok, _policy_set} =
      GovernanceStore.upsert_policy_set(%{
        managed_repo_id: managed_repo.id,
        name: "default",
        review_policy: %{
          mode: "auto_post",
          requires_human_approval: false,
          change_request_required: false,
          review_threshold: "auto_post",
          required_stage: "approval",
          source: "admin_override"
        }
      })

    {:ok, _repo_posture} =
      GovernanceStore.upsert_repo_posture(%{
        managed_repo_id: managed_repo.id,
        summary: "Repo posture allows autonomous issue triage.",
        overall_trust: "high",
        execution_readiness: "high",
        validation_reliability: "high",
        review_burden: "low",
        drift_rate: "low",
        recovery_resilience: "high",
        requirements_confidence: "high",
        supervision_mode: "autonomous",
        escalation_status: "normal",
        contributing_check_ids: [],
        posture_metadata: %{}
      })

    policy_state =
      IssueTriageWorkflowKickoff.policy_state(%{
        id: project.id,
        managed_repo_id: managed_repo.id,
        settings: project.settings
      })

    assert policy_state.enabled == true
    assert policy_state.approval_policy.mode == "auto_post"
    assert policy_state.approval_policy.change_request_required == false
    assert policy_state.approval_policy.source == "repo_posture.autonomous"
  end

  defp setup_product_store do
    store_name = :"policy_set_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_policy_set/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
