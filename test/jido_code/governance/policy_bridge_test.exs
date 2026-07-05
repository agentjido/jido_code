defmodule JidoCode.Governance.PolicyBridgeTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.policy_layers.repository_governance_policy_is_repo_control_layer
  # covers: architecture.policy_layers.repo_posture_can_shape_effective_review_policy
  # covers: architecture.repo_posture.supervision_modes_are_explicit_and_reversible
  # covers: architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich
  # covers: architecture.vsm_recursion.algedonic_escalation
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.ManagedRepoStore
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Governance.{PolicyBridge, PostureBridge}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project

  setup do
    setup_product_store()
  end

  test "strong posture can progress to autonomous supervision and preserve auto-post governance" do
    workspace_path = create_workspace_path!("autonomous")
    seed_spec_state!(workspace_path, threshold_failures: 0, findings: 0)

    {:ok, project} =
      Project.create(%{
        name: "repo-policy-autonomous",
        github_full_name: "owner/repo-policy-autonomous",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"approval_mode" => "auto_post"}
          },
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)

    assert {:ok, %{assessment: _assessment}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               actor: %{id: "operator-autonomous", email: "auto@example.com"},
               payload: %{"workflow_name" => "fix_failing_tests", "failure_signal" => "mix test"}
             })

    assert {:ok, %{repo_posture: repo_posture}} = PostureBridge.sync_managed_repo(managed_repo)

    assert repo_posture.supervision_mode == "autonomous"
    assert repo_posture.escalation_status == "normal"

    assert {:ok, review_policy} = PolicyBridge.review_policy_for_managed_repo(managed_repo.id)
    assert review_policy["mode"] == "auto_post"
    assert review_policy["supervision_mode"] == "autonomous"
    assert review_policy["escalation_status"] == "normal"
    assert review_policy["posture_override"] == true
  end

  test "viability threats downgrade to directed supervision and force approval-required review" do
    workspace_path = create_workspace_path!("directed")
    seed_spec_state!(workspace_path, threshold_failures: 2, findings: 1)

    {:ok, project} =
      Project.create(%{
        name: "repo-policy-directed",
        github_full_name: "owner/repo-policy-directed",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"approval_mode" => "auto_post"}
          },
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)

    assert {:ok, %{repo_posture: repo_posture}} = PostureBridge.sync_managed_repo(managed_repo)

    assert repo_posture.supervision_mode == "directed"
    assert repo_posture.escalation_status == "algedonic"
    assert is_binary(repo_posture.algedonic_check_id)

    assert {:ok, review_policy} = PolicyBridge.review_policy_for_managed_repo(managed_repo.id)
    assert review_policy["mode"] == "approval_required"
    assert review_policy["change_request_required"] == true
    assert review_policy["requires_human_approval"] == true
    assert review_policy["supervision_mode"] == "directed"
    assert review_policy["escalation_status"] == "algedonic"
    assert review_policy["posture_override"] == true
  end

  defp create_workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-five-policy-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp seed_spec_state!(workspace_path, opts) do
    spec_dir = Path.join(workspace_path, ".spec")
    specs_dir = Path.join(spec_dir, "specs")
    decisions_dir = Path.join(spec_dir, "decisions")

    File.mkdir_p!(specs_dir)
    File.mkdir_p!(decisions_dir)

    File.write!(Path.join(specs_dir, "factory_control_plane.spec.md"), "# Factory Control Plane\n")
    File.write!(Path.join(decisions_dir, "factory_control_plane.md"), "# ADR\n")

    findings = Keyword.get(opts, :findings, 0)
    threshold_failures = Keyword.get(opts, :threshold_failures, 0)

    state = %{
      "summary" => %{
        "subjects" => 1,
        "decisions" => 1,
        "requirements" => 6,
        "scenarios" => 3,
        "findings" => findings
      },
      "workspace" => %{
        "spec_count" => 1,
        "decision_count" => 1
      },
      "verification" => %{
        "threshold_failures" => threshold_failures,
        "strength_summary" => %{"linked" => 3, "claimed" => 0, "executed" => 0},
        "claims" => [%{"subject_id" => "architecture.factory_control_plane"}]
      }
    }

    File.write!(Path.join(spec_dir, "state.json"), Jason.encode!(state))
  end

  defp setup_product_store do
    store_name = :"policy_bridge_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_policy_bridge/#{store_name}")

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
