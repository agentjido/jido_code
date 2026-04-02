defmodule JidoCode.Governance.PostureBridgeTest do
  # covers: architecture.repo_posture.repo_posture_summarizes_trust_dimensions
  # covers: architecture.repo_posture.posture_checks_preserve_explainable_links
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{Evidence, PostureBridge, PostureCheck, RepoPosture}
  alias JidoCode.Operations.{Ingress, Observation}
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "repo posture and posture checks stay explainable across observations assessments and evidence" do
    workspace_path = create_workspace_path!()
    seed_spec_state!(workspace_path)

    {:ok, project} =
      Project.create(%{
        name: "repo-posture",
        github_full_name: "owner/repo-posture",
        default_branch: "main",
        settings: %{
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

    assert {:ok, base_posture} =
             RepoPosture.get_by_managed_repo_id(managed_repo.id, actor: Actor.operator_actor())

    assert base_posture.execution_readiness == "high"
    assert base_posture.validation_reliability == "high"
    assert base_posture.review_burden == "high"
    assert base_posture.requirements_confidence == "medium"

    assert {:ok, %{assessment: assessment, work_item: work_item}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "conversation",
               intent: "coding_turn_request",
               actor: %{id: "operator-posture", email: "posture@example.com"},
               payload: %{"objective" => "Stabilize posture computation."}
             })

    assert {:ok, workflow_run} =
             WorkflowRun.create(%{
               run_id: "posture-run-#{System.unique_integer([:positive])}",
               project_id: project.id,
               managed_repo_id: managed_repo.id,
               workflow_name: "fix_failing_tests",
               workflow_version: 1,
               trigger: %{"source" => "test"},
               inputs: %{"work_item_id" => work_item.id},
               input_metadata: %{},
               initiating_actor: %{"id" => "operator-posture", "actor_class" => "operator"},
               current_step: "validate_repo",
               error: %{
                 "detail" => "Validation failed in test posture flow.",
                 "error_type" => "tests_failed",
                 "remediation" => "Review governed failure context before retry.",
                 "event_channel_diagnostics" => [%{"detail" => "phase 5 posture bridge synthetic failure"}]
               },
               started_at: DateTime.utc_now() |> DateTime.truncate(:second)
             })

    assert workflow_run.error["detail"] =~ "Validation failed"

    assert {:ok, [failure_evidence]} =
             Evidence.read(
               query: [
                 filter: [managed_repo_id: managed_repo.id, key: "failure_context"],
                 sort: [recorded_at: :desc],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert {:ok, [spec_observation]} =
             Observation.read(
               query: [
                 filter: [managed_repo_id: managed_repo.id, source: "repo_native", category: "spec_led_state"],
                 sort: [observed_at: :desc],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert {:ok, %{repo_posture: refreshed_posture, posture_checks: posture_checks}} =
             PostureBridge.sync_managed_repo(managed_repo)

    assert refreshed_posture.validation_reliability == "high"
    assert refreshed_posture.recovery_resilience == "low"
    assert refreshed_posture.requirements_confidence == "high"

    assert refreshed_posture.contributing_check_ids |> Enum.sort() ==
             posture_checks |> Enum.map(& &1.id) |> Enum.sort()

    validation_check = posture_check(posture_checks, "validation_reliability")
    requirements_check = posture_check(posture_checks, "requirements_confidence")
    recovery_check = posture_check(posture_checks, "recovery_resilience")

    assert validation_check.observation_id == spec_observation.id
    assert requirements_check.assessment_id == assessment.id
    assert recovery_check.evidence_id == failure_evidence.id

    assert {:ok, persisted_posture} =
             RepoPosture.get_by_managed_repo_id(managed_repo.id, actor: Actor.operator_actor())

    assert persisted_posture.summary =~ "Repo posture is"

    assert {:ok, persisted_checks} =
             PostureCheck.read(
               query: [filter: [managed_repo_id: managed_repo.id]],
               actor: Actor.operator_actor()
             )

    assert length(persisted_checks) == 7
  end

  test "runtime capability posture can lower readiness and force review without collapsing product governance into runtime policy" do
    workspace_path = create_workspace_path!()
    seed_spec_state!(workspace_path)

    {:ok, project} =
      Project.create(%{
        name: "repo-posture-runtime-capability",
        github_full_name: "owner/repo-posture-runtime-capability",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          },
          "support_agent_config" => %{
            "github_issue_bot" => %{"approval_mode" => "auto_post"}
          },
          "runtime_capabilities" => %{
            "required_services" => ["coding_assistance_service", "missing_runtime_service"]
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, %{repo_posture: repo_posture, posture_checks: posture_checks}} =
             PostureBridge.sync_managed_repo(managed_repo)

    assert repo_posture.execution_readiness == "low"
    assert repo_posture.review_burden == "high"
    assert repo_posture.supervision_mode == "guided"
    assert repo_posture.escalation_status == "review"
    assert repo_posture.posture_metadata["runtime_capability_state"]["status"] == "blocked"
    assert repo_posture.posture_metadata["runtime_capability_summary"] =~ "missing_runtime_service"

    execution_check = posture_check(posture_checks, "execution_readiness")
    review_check = posture_check(posture_checks, "review_burden")

    assert execution_check.source == "runtime_capability.execution"
    assert review_check.source == "governance.review_policy+runtime_capability"
    assert execution_check.observation_id == review_check.observation_id
    assert execution_check.details["runtime_capability_state"]["status"] == "blocked"
    assert review_check.details["runtime_capability_state"]["blocked_service_count"] == 1
  end

  defp posture_check(posture_checks, dimension) do
    Enum.find(posture_checks, &(&1.dimension == dimension))
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-five-posture-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp seed_spec_state!(workspace_path) do
    spec_dir = Path.join(workspace_path, ".spec")
    specs_dir = Path.join(spec_dir, "specs")
    decisions_dir = Path.join(spec_dir, "decisions")

    File.mkdir_p!(specs_dir)
    File.mkdir_p!(decisions_dir)

    File.write!(Path.join(specs_dir, "factory_control_plane.spec.md"), "# Factory Control Plane\n")
    File.write!(Path.join(specs_dir, "repo_posture.spec.md"), "# Repo Posture\n")
    File.write!(Path.join(decisions_dir, "factory_control_plane.md"), "# ADR\n")

    state = %{
      "summary" => %{
        "subjects" => 2,
        "decisions" => 1,
        "requirements" => 8,
        "scenarios" => 4,
        "findings" => 0
      },
      "workspace" => %{
        "spec_count" => 2,
        "decision_count" => 1
      },
      "verification" => %{
        "threshold_failures" => 0,
        "strength_summary" => %{"linked" => 6, "claimed" => 0, "executed" => 0},
        "claims" => [%{"subject_id" => "architecture.factory_control_plane"}]
      }
    }

    File.write!(Path.join(spec_dir, "state.json"), Jason.encode!(state))
  end
end
