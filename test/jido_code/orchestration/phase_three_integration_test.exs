defmodule JidoCode.Orchestration.PhaseThreeIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.run_governance.run_launch_resolves_effective_execution_profile
  # covers: architecture.run_governance.run_projection_preserves_explicit_stage_catalog
  # covers: architecture.execution_pipeline.run_is_projection_of_workflow_state
  # covers: architecture.run_governance.evidence_records_capture_run_outputs
  # covers: architecture.run_governance.change_request_records_reviewable_run_state
  # covers: architecture.run_governance.decision_records_capture_governance_outcomes
  # covers: architecture.run_governance.review_policy_controls_change_request_creation
  # covers: architecture.run_governance.blocked_review_context_preserves_typed_remediation
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{ChangeRequest, Decision, Evidence, PolicySet}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Orchestration.{ExecutionProfile, Run, RunBridge, WorkflowRun}
  alias JidoCode.Projects.Project

  test "work item launch resolves governed execution profile and preserves explicit stages under runic" do
    governed_stages = [
      "repo_attach",
      "repo_sync",
      "repo_prep",
      "plan",
      "implement",
      "validation",
      "approval",
      "cleanup"
    ]

    {:ok, project} =
      Project.create(%{
        name: "repo-phase-three-launch",
        github_full_name: "owner/repo-phase-three-launch",
        default_branch: "main",
        settings: %{
          "execution" => %{
            "sandbox_profile" => %{"shape" => "standard"},
            "repo_prep_plan" => ["repo_attach", "repo_sync", "repo_prep"],
            "validation_plan" => ["lint", "tests", "spec_check"],
            "governed_stages" => governed_stages
          },
          "workflow" => %{
            "fix_failing_tests" => %{
              "sandbox_profile" => %{"shape" => "large"},
              "validation_plan" => ["tests"],
              "governed_stages" => governed_stages
            }
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, work_item} = record_work_item(project, "operator-launch")

    {:ok, %{workflow_run: workflow_run, run: run}} =
      RunBridge.launch_work_item(work_item, %{
        workflow_name: "fix_failing_tests",
        inputs: %{"failure_signal" => "mix test test/example_test.exs"},
        initiating_actor: %{id: "operator-launch", email: "launch@example.com"}
      })

    {:ok, execution_profile} =
      ExecutionProfile.get_by_managed_repo_name(
        managed_repo.id,
        "workflow:fix_failing_tests",
        actor: Actor.operator_actor()
      )

    assert workflow_run.inputs["work_item_id"] == work_item.id
    assert run.work_item_id == work_item.id
    assert run.execution_profile_id == execution_profile.id
    assert run.execution_engine == "jido_runic"
    assert run.workflow_state_ref["engine"] == "jido_runic"
    assert execution_profile.sandbox_profile["engine"] == "jido_runic"
    assert execution_profile.sandbox_profile["shape"] == "large"
    assert run.governed_stages == governed_stages
    assert run.run_metadata["governed_stages"] == governed_stages
    assert run.run_metadata["repo_prep_plan"] == ["repo_attach", "repo_sync", "repo_prep"]
    assert run.run_metadata["validation_plan"] == ["tests"]
    assert run.current_stage == "repo_prep"
    assert run.stage_statuses["repo_attach"] == "completed"
    assert run.stage_statuses["repo_sync"] == "completed"
    assert run.stage_statuses["repo_prep"] == "active"
    assert run.stage_statuses["validation"] == "pending"
  end

  test "awaiting approval for a work item linked run creates evidence, change requests, and approval decisions" do
    {:ok, project} = create_project("repo-phase-three-approval")
    {:ok, managed_repo} = managed_repo_for_project(project)
    {:ok, work_item} = record_work_item(project, "operator-approval")

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        managed_repo_id: managed_repo.id,
        run_id: "phase-three-approval-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{"source" => "work_item", "mode" => "governed", "work_item_id" => work_item.id},
        inputs: %{
          "work_item_id" => work_item.id,
          "task_summary" => "Implement governed approval flow"
        },
        input_metadata: %{
          "work_item_id" => %{"required" => true, "source" => "work_item"},
          "task_summary" => %{"required" => true, "source" => "test"}
        },
        initiating_actor: %{id: "operator-approval", email: "approval@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 23:00:00Z],
        step_results: %{
          "diff_summary" => "3 files changed (+40/-6).",
          "test_summary" => "mix test: 24 passed, 0 failed.",
          "risk_notes" => ["Touches governed run projection paths."],
          "approval_context" => %{
            "detail" => "Ready for human review.",
            "proposed_comment" => "This run is ready for approval."
          }
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-03-31 23:01:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 23:02:00Z]
      })

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())

    {:ok, evidence_records} =
      Evidence.read(query: [filter: [run_id: run.id], sort: [key: :asc]], actor: Actor.operator_actor())

    {:ok, change_request} = ChangeRequest.get_by_run_id(run.id, actor: Actor.operator_actor())

    assert Enum.map(evidence_records, & &1.key) == [
             "approval_context",
             "diff_summary",
             "risk_notes",
             "test_summary"
           ]

    assert change_request.work_item_id == work_item.id
    assert change_request.status == :open
    assert change_request.request_metadata["review_policy"]["mode"] == "approval_required"
    assert change_request.review_context["current_step"] == "approval_gate"

    {:ok, _approved_workflow_run} =
      WorkflowRun.approve(workflow_run, %{
        actor: %{id: "admin-approval", email: "admin-approval@example.com"},
        approved_at: ~U[2026-03-31 23:03:00Z]
      })

    {:ok, approved_change_request} =
      ChangeRequest.get_by_run_id(run.id, actor: Actor.operator_actor())

    {:ok, [decision]} =
      Decision.read(
        query: [filter: [run_id: run.id], sort: [decided_at: :desc]],
        actor: Actor.operator_actor()
      )

    assert approved_change_request.status == :approved
    assert decision.decision == :approve
    assert decision.change_request_id == approved_change_request.id
    assert decision.actor["id"] == "admin-approval"
    assert decision.work_item_id == work_item.id
  end

  test "rejection persists durable decision records with actor attribution for governed runs" do
    {:ok, project} = create_project("repo-phase-three-rejection")
    {:ok, managed_repo} = managed_repo_for_project(project)
    {:ok, work_item} = record_work_item(project, "operator-rejection")

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        managed_repo_id: managed_repo.id,
        run_id: "phase-three-reject-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{"source" => "work_item", "mode" => "governed", "work_item_id" => work_item.id},
        inputs: %{
          "work_item_id" => work_item.id,
          "task_summary" => "Exercise rejection governance"
        },
        input_metadata: %{
          "work_item_id" => %{"required" => true, "source" => "work_item"},
          "task_summary" => %{"required" => true, "source" => "test"}
        },
        initiating_actor: %{id: "operator-rejection", email: "rejection@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 23:10:00Z],
        step_results: %{
          "diff_summary" => "1 file changed (+8/-1).",
          "test_summary" => "mix test: 8 passed, 0 failed.",
          "risk_notes" => ["Review requested before deploy."],
          "approval_context" => %{"detail" => "Awaiting rejection flow review."}
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "run_spec_check",
        transitioned_at: ~U[2026-03-31 23:11:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 23:12:00Z]
      })

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())

    {:ok, _rejected_workflow_run} =
      WorkflowRun.reject(workflow_run, %{
        actor: %{id: "admin-reject", email: "admin-reject@example.com"},
        rejected_at: ~U[2026-03-31 23:13:00Z],
        rationale: "Validation needs a broader test sweep."
      })

    {:ok, change_request} = ChangeRequest.get_by_run_id(run.id, actor: Actor.operator_actor())

    {:ok, [decision]} =
      Decision.read(
        query: [filter: [run_id: run.id], sort: [decided_at: :desc]],
        actor: Actor.operator_actor()
      )

    assert change_request.status == :rejected
    assert decision.decision == :reject
    assert decision.actor["id"] == "admin-reject"
    assert decision.rationale == "Validation needs a broader test sweep."
    assert decision.change_request_id == change_request.id
    assert decision.work_item_id == work_item.id
  end

  test "repo review policy controls change requests while blocked review paths preserve typed remediation" do
    {:ok, auto_post_project} = create_project("repo-phase-three-auto-post")
    {:ok, auto_post_managed_repo} = managed_repo_for_project(auto_post_project)
    {:ok, auto_post_work_item} = record_work_item(auto_post_project, "operator-auto-post")

    assert {:ok, _policy_set} =
             PolicySet.upsert_default_for_managed_repo(
               %{
                 managed_repo_id: auto_post_managed_repo.id,
                 review_policy: %{
                   mode: "auto_post",
                   requires_human_approval: false,
                   change_request_required: false,
                   review_threshold: "auto_post",
                   required_stage: "approval",
                   source: "phase_three_integration_override"
                 }
               },
               actor: Actor.admin_actor()
             )

    {:ok, auto_post_run_record} =
      WorkflowRun.create(%{
        project_id: auto_post_project.id,
        managed_repo_id: auto_post_managed_repo.id,
        run_id: "phase-three-auto-post-#{System.unique_integer([:positive])}",
        workflow_name: "issue_triage",
        workflow_version: 1,
        trigger: %{"source" => "work_item", "mode" => "governed", "work_item_id" => auto_post_work_item.id},
        inputs: %{
          "work_item_id" => auto_post_work_item.id,
          "issue_reference" => "owner/repo-phase-three-auto-post#7"
        },
        input_metadata: %{
          "work_item_id" => %{"required" => true, "source" => "work_item"},
          "issue_reference" => %{"required" => true, "source" => "test"}
        },
        initiating_actor: %{id: "operator-auto-post", email: "autopost@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 23:20:00Z],
        step_results: %{
          "diff_summary" => "1 file changed (+3/-0).",
          "test_summary" => "No code execution required.",
          "risk_notes" => ["Auto-post should suppress change requests."]
        }
      })

    {:ok, auto_post_run_record} =
      WorkflowRun.transition_status(auto_post_run_record, %{
        to_status: :running,
        current_step: "compose_issue_response",
        transitioned_at: ~U[2026-03-31 23:21:00Z]
      })

    {:ok, _auto_post_run_record} =
      WorkflowRun.transition_status(auto_post_run_record, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 23:22:00Z]
      })

    {:ok, auto_post_run} =
      Run.get_by_workflow_run_id(auto_post_run_record.id, actor: Actor.operator_actor())

    assert {:ok, []} =
             ChangeRequest.read(
               query: [filter: [run_id: auto_post_run.id]],
               actor: Actor.operator_actor()
             )

    {:ok, blocked_project} = create_project("repo-phase-three-blocked-review")
    {:ok, blocked_managed_repo} = managed_repo_for_project(blocked_project)
    {:ok, blocked_work_item} = record_work_item(blocked_project, "operator-blocked")

    {:ok, blocked_workflow_run} =
      WorkflowRun.create(%{
        project_id: blocked_project.id,
        managed_repo_id: blocked_managed_repo.id,
        run_id: "phase-three-blocked-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{"source" => "work_item", "mode" => "governed", "work_item_id" => blocked_work_item.id},
        inputs: %{
          "work_item_id" => blocked_work_item.id,
          "task_summary" => "Exercise blocked review remediation"
        },
        input_metadata: %{
          "work_item_id" => %{"required" => true, "source" => "work_item"},
          "task_summary" => %{"required" => true, "source" => "test"}
        },
        initiating_actor: %{id: "operator-blocked", email: "blocked@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 23:30:00Z],
        step_results: %{
          "approval_context_generation_error" =>
            "Approval context generation failed because validation artifacts were incomplete."
        }
      })

    {:ok, blocked_workflow_run} =
      WorkflowRun.transition_status(blocked_workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-03-31 23:31:00Z]
      })

    {:ok, blocked_workflow_run} =
      WorkflowRun.transition_status(blocked_workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 23:32:00Z]
      })

    {:ok, blocked_run} =
      Run.get_by_workflow_run_id(blocked_workflow_run.id, actor: Actor.operator_actor())

    {:ok, blocked_change_request} =
      ChangeRequest.get_by_run_id(blocked_run.id, actor: Actor.operator_actor())

    assert blocked_change_request.request_metadata["review_blocked"] == true

    assert blocked_change_request.review_context["blocking_diagnostic"]["error_type"] ==
             "approval_context_generation_failed"

    assert blocked_change_request.review_context["blocking_diagnostic"]["remediation"] =~
             "diff summary"
  end

  defp create_project(name, settings \\ %{}) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
      default_branch: "main",
      settings: settings
    })
  end

  defp managed_repo_for_project(project) do
    ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())
  end

  defp record_work_item(project, actor_id) do
    with {:ok, %{work_item: work_item}} <-
           Ingress.record_operator_intake(%{
             channel: "workflows",
             intent: "manual_run_request",
             project_id: project.id,
             actor: %{id: actor_id, email: "#{actor_id}@example.com"},
             payload: %{
               "task_summary" => "Phase three integration work item",
               "workflow_name" => "implement_task"
             },
             source_metadata: %{
               "trigger" => %{"source" => "phase_three_integration_test"}
             }
           }) do
      {:ok, work_item}
    end
  end
end
