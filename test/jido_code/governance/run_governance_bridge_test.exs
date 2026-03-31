defmodule JidoCode.Governance.RunGovernanceBridgeTest do
  # covers: architecture.run_governance.evidence_records_capture_run_outputs
  # covers: architecture.run_governance.change_request_records_reviewable_run_state
  # covers: architecture.run_governance.decision_records_capture_governance_outcomes
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.Actor
  alias JidoCode.Governance.{ChangeRequest, Decision, Evidence}
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project

  test "awaiting approval creates evidence and a reviewable change request" do
    {:ok, project} = create_project("repo-governed-review")

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-review-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Prepare review evidence"},
        input_metadata: %{"task_summary" => %{required: true, source: "test"}},
        initiating_actor: %{id: "operator-1", email: "operator@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 19:00:00Z],
        step_results: %{
          "diff_summary" => "4 files changed (+52/-8).",
          "test_summary" => "mix test: 18 passed, 0 failed.",
          "risk_notes" => [
            "Touches repo sync and run projection code.",
            "No credential paths changed."
          ]
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-03-31 19:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 19:02:00Z]
      })

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())

    {:ok, evidence_records} =
      Evidence.read(query: [filter: [run_id: run.id], sort: [key: :asc]], actor: Actor.operator_actor())

    assert Enum.map(evidence_records, & &1.key) == [
             "approval_context",
             "diff_summary",
             "risk_notes",
             "test_summary"
           ]

    {:ok, change_request} = ChangeRequest.get_by_run_id(run.id, actor: Actor.operator_actor())

    assert change_request.status == :open
    assert change_request.summary =~ run.run_id
    assert change_request.review_context["current_step"] == "approval_gate"
    assert is_list(change_request.evidence_ids)
    assert length(change_request.evidence_ids) == 4
  end

  test "approval outcomes create durable decisions and resolve the change request" do
    {:ok, project} = create_project("repo-governed-decision")

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-decision-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Persist decision records"},
        input_metadata: %{"task_summary" => %{required: true, source: "test"}},
        initiating_actor: %{id: "operator-2", email: "operator2@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 20:00:00Z],
        step_results: %{
          "diff_summary" => "2 files changed (+14/-2).",
          "test_summary" => "mix test: 12 passed, 0 failed.",
          "risk_notes" => ["Touches review-state storage."]
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-03-31 20:01:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 20:02:00Z]
      })

    {:ok, _approved_run} =
      WorkflowRun.approve(workflow_run, %{
        actor: %{id: "admin-1", email: "admin@example.com"},
        approved_at: ~U[2026-03-31 20:03:00Z]
      })

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())
    {:ok, change_request} = ChangeRequest.get_by_run_id(run.id, actor: Actor.operator_actor())

    {:ok, [decision]} =
      Decision.read(
        query: [filter: [run_id: run.id], sort: [decided_at: :desc]],
        actor: Actor.operator_actor()
      )

    assert change_request.status == :approved

    assert DateTime.compare(
             DateTime.truncate(change_request.resolved_at, :second),
             ~U[2026-03-31 20:03:00Z]
           ) == :eq

    assert decision.decision == :approve
    assert decision.change_request_id == change_request.id
    assert decision.actor["id"] == "admin-1"
    assert length(decision.evidence_ids) >= 3
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
