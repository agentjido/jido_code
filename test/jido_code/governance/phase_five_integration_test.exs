defmodule JidoCode.Governance.PhaseFiveIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.repo_posture.repo_native_observations_capture_current_truth_signals
  # covers: architecture.repo_posture.repo_posture_summarizes_trust_dimensions
  # covers: architecture.repo_posture.posture_checks_preserve_explainable_links
  # covers: architecture.repo_posture.supervision_modes_are_explicit_and_reversible
  # covers: architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich
  # covers: architecture.vsm_recursion.algedonic_escalation
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{Evidence, PolicyBridge, PostureCheck, PostureBridge, RepoPosture}
  alias JidoCode.Operations.{Ingress, RepoNativeState}
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "verified repo-native state informs assessments, stays predictable without beadwork, and can progress to autonomous supervision" do
    workspace_path = create_workspace_path!("stable")
    seed_spec_state!(workspace_path, threshold_failures: 0, findings: 0)

    {:ok, project} =
      Project.create(%{
        name: "repo-phase-five-stable",
        github_full_name: "owner/repo-phase-five-stable",
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

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, initial_snapshot} = RepoNativeState.latest_signal_snapshot(managed_repo.id)
    assert initial_snapshot["spec_led"]["status"] == "verified"
    assert initial_snapshot["beadwork"]["present"] == false

    assert {:ok, %{assessment: first_assessment, work_item: work_item}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               actor: %{id: "operator-stable", email: "stable@example.com"},
               payload: %{"workflow_name" => "fix_failing_tests", "failure_signal" => "mix test"}
             })

    assert first_assessment.inputs["repo_native_state"]["beadwork"]["present"] == false

    seed_beadwork_state!(workspace_path, work_item.id)

    assert {:ok, _repo_native_state} = RepoNativeState.sync_managed_repo(managed_repo)

    assert {:ok, %{assessment: second_assessment}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               actor: %{id: "operator-stable", email: "stable@example.com"},
               payload: %{"workflow_name" => "fix_failing_tests", "failure_signal" => "mix test"}
             })

    assert second_assessment.inputs["repo_native_state"]["beadwork"]["status"] == "aligned"
    assert second_assessment.inputs["repo_native_state"]["beadwork"]["aligned_open_work_item_ids"] == [work_item.id]

    assert {:ok, repo_posture} =
             RepoPosture.get_by_managed_repo_id(managed_repo.id, actor: Actor.operator_actor())

    assert repo_posture.supervision_mode == "autonomous"
    assert repo_posture.escalation_status == "normal"
    assert length(repo_posture.contributing_check_ids) == 7
  end

  test "blocked repo-native state and failure evidence trigger directed supervision with algedonic escalation linkage" do
    workspace_path = create_workspace_path!("threat")
    seed_spec_state!(workspace_path, threshold_failures: 2, findings: 1)

    {:ok, project} =
      Project.create(%{
        name: "repo-phase-five-threat",
        github_full_name: "owner/repo-phase-five-threat",
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

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, %{assessment: assessment, work_item: work_item}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               actor: %{id: "operator-threat", email: "threat@example.com"},
               payload: %{"workflow_name" => "fix_failing_tests", "failure_signal" => "mix test"}
             })

    assert {:ok, _workflow_run} =
             WorkflowRun.create(%{
               run_id: "phase-five-threat-#{System.unique_integer([:positive])}",
               project_id: project.id,
               managed_repo_id: managed_repo.id,
               workflow_name: "fix_failing_tests",
               workflow_version: 1,
               trigger: %{"source" => "integration_test"},
               inputs: %{"work_item_id" => work_item.id},
               input_metadata: %{},
               initiating_actor: %{"id" => "operator-threat", "actor_class" => "operator"},
               current_step: "validate_repo",
               error: %{
                 "detail" => "Governed failure evidence captured for algedonic review.",
                 "error_type" => "tests_failed",
                 "remediation" => "Escalate to operator review."
               },
               started_at: DateTime.utc_now() |> DateTime.truncate(:second)
             })

    assert {:ok, [failure_evidence]} =
             Evidence.read(
               query: [
                 filter: [managed_repo_id: managed_repo.id, key: "failure_context"],
                 sort: [recorded_at: :desc],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert {:ok, %{repo_posture: repo_posture}} = PostureBridge.sync_managed_repo(managed_repo)
    assert repo_posture.supervision_mode == "directed"
    assert repo_posture.escalation_status == "algedonic"
    assert is_binary(repo_posture.algedonic_check_id)

    assert {:ok, [algedonic_check]} =
             PostureCheck.read(
               query: [filter: [id: repo_posture.algedonic_check_id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert algedonic_check.dimension == "algedonic_escalation"
    assert algedonic_check.escalation_mode == "algedonic"
    assert algedonic_check.threat_level == "viability"
    assert algedonic_check.evidence_id == failure_evidence.id
    assert algedonic_check.assessment_id == assessment.id

    assert {:ok, review_policy} = PolicyBridge.review_policy_for_managed_repo(managed_repo.id)
    assert review_policy["mode"] == "approval_required"
    assert review_policy["requires_human_approval"] == true
    assert review_policy["supervision_mode"] == "directed"
    assert review_policy["escalation_status"] == "algedonic"
    assert review_policy["posture_override"] == true
  end

  defp create_workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-five-integration-#{suffix}-#{System.unique_integer([:positive])}"
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
    File.write!(Path.join(specs_dir, "repo_posture.spec.md"), "# Repo Posture\n")
    File.write!(Path.join(decisions_dir, "factory_control_plane.md"), "# ADR\n")

    findings = Keyword.get(opts, :findings, 0)
    threshold_failures = Keyword.get(opts, :threshold_failures, 0)

    state = %{
      "summary" => %{
        "subjects" => 2,
        "decisions" => 1,
        "requirements" => 10,
        "scenarios" => 5,
        "findings" => findings
      },
      "workspace" => %{
        "spec_count" => 2,
        "decision_count" => 1
      },
      "verification" => %{
        "threshold_failures" => threshold_failures,
        "strength_summary" => %{"linked" => 8, "claimed" => 0, "executed" => 0},
        "claims" => [%{"subject_id" => "architecture.repo_posture"}]
      }
    }

    File.write!(Path.join(spec_dir, "state.json"), Jason.encode!(state))
  end

  defp seed_beadwork_state!(workspace_path, work_item_id) do
    beadwork_dir = Path.join(workspace_path, ".beadwork")
    File.mkdir_p!(Path.join(beadwork_dir, "work"))

    File.write!(
      Path.join(workspace_path, "memory.md"),
      """
      # Memory

      work_item_id: #{work_item_id}
      """
    )

    File.write!(
      Path.join([beadwork_dir, "work", "stable-posture.md"]),
      """
      # Stable posture follow-up

      work_item_id: #{work_item_id}
      """
    )
  end
end
