defmodule JidoCode.Orchestration.RunBridgeTest do
  # covers: architecture.run_governance.run_is_preferred_execution_record
  # covers: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  # covers: architecture.run_governance.execution_profile_governs_environment_defaults
  # covers: architecture.run_governance.execution_profile_preserves_repo_and_workflow_compatibility
  # covers: architecture.run_governance.run_launch_resolves_effective_execution_profile
  # covers: architecture.execution_pipeline.run_is_projection_of_workflow_state
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Orchestration.{ExecutionProfile, Run, RunBridge, WorkflowRun}
  alias JidoCode.Projects.Project

  test "workflow runs project into governed runs with execution profiles and stage state" do
    {:ok, project} =
      Project.create(%{
        name: "repo-run-projection",
        github_full_name: "owner/repo-run-projection",
        default_branch: "main",
        settings: %{
          "execution" => %{
            "sandbox_profile" => %{"shape" => "standard"},
            "repo_prep_plan" => ["repo_attach", "repo_sync", "repo_prep"],
            "validation_plan" => ["lint", "tests", "spec_check"],
            "checkpoint_strategy" => "resume_from_checkpoint"
          },
          "workflow" => %{
            "issue_triage" => %{
              "sandbox_profile" => %{"shape" => "light"},
              "validation_plan" => ["spec_check"]
            }
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-governed-#{System.unique_integer([:positive])}",
        workflow_name: "issue_triage",
        workflow_version: 1,
        trigger: %{"source" => "github_webhook", "mode" => "webhook"},
        inputs: %{"issue_reference" => "owner/repo-run-projection#11"},
        input_metadata: %{"issue_reference" => %{"required" => true, "source" => "test"}},
        initiating_actor: %{id: "operator-1", email: "operator@example.com"},
        current_step: "run_spec_check",
        started_at: ~U[2026-03-31 18:00:00Z]
      })

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())

    {:ok, execution_profile} =
      ExecutionProfile.get_by_managed_repo_name(
        managed_repo.id,
        "workflow:issue_triage",
        actor: Actor.operator_actor()
      )

    assert run.managed_repo_id == managed_repo.id
    assert run.execution_profile_id == execution_profile.id
    assert run.legacy_project_id == project.id
    assert run.run_id == workflow_run.run_id
    assert run.execution_engine == "jido_runic"
    assert run.current_stage == "validation"
    assert run.stage_statuses["validation"] == "active"
    assert run.workflow_state_ref["workflow_run_id"] == workflow_run.id
    assert run.run_metadata["execution_profile_name"] == "workflow:issue_triage"
    assert run.run_metadata["workflow_audit"]["status_transitions"] != []
    assert run.run_metadata["workflow_audit"]["step_results"] == %{}
    assert run.run_metadata["workflow_audit"]["error"] == %{}
    assert run.run_metadata["repo_prep_plan"] == ["repo_attach", "repo_sync", "repo_prep"]
    assert run.run_metadata["validation_plan"] == ["spec_check"]
    assert execution_profile.sandbox_profile["shape"] == "light"
    assert execution_profile.validation_plan == ["spec_check"]
    assert execution_profile.checkpoint_strategy == "resume_from_checkpoint"

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_triage",
        transitioned_at: ~U[2026-03-31 18:03:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 18:05:00Z]
      })

    {:ok, updated_run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())

    assert updated_run.status == :awaiting_approval
    assert updated_run.current_stage == "approval"
    assert updated_run.stage_statuses["approval"] == "awaiting_decision"

    assert List.last(updated_run.run_metadata["workflow_audit"]["status_transitions"])["to_status"] ==
             "awaiting_approval"
  end

  test "governed work item launch creates linked workflow and run projections" do
    {:ok, project} =
      Project.create(%{
        name: "repo-work-launch",
        github_full_name: "owner/repo-work-launch",
        default_branch: "main",
        settings: %{
          "execution" => %{
            "sandbox_profile" => %{"shape" => "standard"},
            "validation_plan" => ["lint", "tests"]
          },
          "workflow" => %{
            "fix_failing_tests" => %{
              "sandbox_profile" => %{"shape" => "large"},
              "validation_plan" => ["tests"]
            }
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, %{work_item: work_item}} =
      Ingress.record_operator_intake(%{
        channel: "workflows",
        intent: "manual_run_request",
        project_id: project.id,
        actor: %{id: "operator-9", email: "operator9@example.com"},
        payload: %{
          "workflow_name" => "fix_failing_tests",
          "failure_signal" => "mix test test/example_test.exs"
        },
        source_metadata: %{
          "trigger" => %{"source" => "run_bridge_test"}
        }
      })

    {:ok, %{workflow_run: workflow_run, run: run}} =
      RunBridge.launch_work_item(work_item, %{
        workflow_name: "fix_failing_tests",
        inputs: %{"failure_signal" => "mix test test/example_test.exs"},
        initiating_actor: %{id: "operator-9", email: "operator9@example.com"}
      })

    {:ok, execution_profile} =
      ExecutionProfile.get_by_managed_repo_name(
        managed_repo.id,
        "workflow:fix_failing_tests",
        actor: Actor.operator_actor()
      )

    assert workflow_run.project_id == project.id
    assert workflow_run.inputs["work_item_id"] == work_item.id
    assert workflow_run.inputs["failure_signal"] == "mix test test/example_test.exs"
    assert run.work_item_id == work_item.id
    assert run.execution_profile_id == execution_profile.id
    assert run.execution_engine == "jido_runic"
    assert run.run_metadata["execution_profile_name"] == "workflow:fix_failing_tests"
    assert execution_profile.sandbox_profile["shape"] == "large"
    assert execution_profile.validation_plan == ["tests"]
  end

end
