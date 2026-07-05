defmodule JidoCode.Governance.RunGovernanceBridgeTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.run_governance.evidence_records_capture_run_outputs
  # covers: architecture.run_governance.change_request_records_reviewable_run_state
  # covers: architecture.run_governance.decision_records_capture_governance_outcomes
  use JidoCode.DataCase, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Governance.RecordStore, as: GovernanceStore
  alias JidoCode.Orchestration.{RecordStore, WorkflowRun}
  alias JidoCode.Projects.Project

  setup do
    setup_product_store()
  end

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

    {:ok, run} = RecordStore.get_run_by_workflow_run_id(workflow_run.id)

    {:ok, evidence_records} =
      GovernanceStore.list_evidence(%{run_id: run.id}, query: [sort: [key: :asc]])

    assert Enum.map(evidence_records, & &1.key) == [
             "approval_context",
             "diff_summary",
             "risk_notes",
             "test_summary"
           ]

    {:ok, change_request} = GovernanceStore.get_change_request_by_run_id(run.id)

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

    {:ok, run} = RecordStore.get_run_by_workflow_run_id(workflow_run.id)
    {:ok, change_request} = GovernanceStore.get_change_request_by_run_id(run.id)

    {:ok, [decision]} =
      GovernanceStore.list_decisions(%{run_id: run.id}, query: [sort: [decided_at: :desc]])

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

  test "auto-post policy suppresses change requests for approval-stage runs" do
    {:ok, project} =
      Project.create(%{
        name: "repo-auto-post",
        github_full_name: "owner/repo-auto-post",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"approval_mode" => "auto_post"}
          }
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-auto-post-#{System.unique_integer([:positive])}",
        workflow_name: "issue_triage",
        workflow_version: 1,
        trigger: %{source: "github_webhook", mode: "webhook"},
        inputs: %{"issue_reference" => "owner/repo-auto-post#11"},
        input_metadata: %{"issue_reference" => %{required: true, source: "test"}},
        initiating_actor: %{id: "operator-3", email: "operator3@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 21:00:00Z],
        step_results: %{
          "diff_summary" => "1 file changed (+8/-0).",
          "test_summary" => "manual triage context only.",
          "risk_notes" => ["Auto-post policy should suppress the change request."]
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-03-31 21:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 21:02:00Z]
      })

    {:ok, run} = RecordStore.get_run_by_workflow_run_id(workflow_run.id)

    assert {:ok, []} = GovernanceStore.list_change_requests(%{run_id: run.id})
  end

  test "blocked approval context preserves typed remediation on the change request" do
    {:ok, project} = create_project("repo-blocked-review")

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-blocked-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Trigger blocked review context"},
        input_metadata: %{"task_summary" => %{required: true, source: "test"}},
        initiating_actor: %{id: "operator-4", email: "operator4@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 22:00:00Z],
        step_results: %{
          "approval_context_generation_error" =>
            "Approval context generation failed because validation artifacts were incomplete."
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-03-31 22:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 22:02:00Z]
      })

    {:ok, run} = RecordStore.get_run_by_workflow_run_id(workflow_run.id)
    {:ok, change_request} = GovernanceStore.get_change_request_by_run_id(run.id)

    assert change_request.request_metadata["review_blocked"] == true

    assert change_request.review_context["blocking_diagnostic"]["error_type"] ==
             "approval_context_generation_failed"

    assert change_request.review_context["blocking_diagnostic"]["remediation"] =~
             "diff summary"
  end

  defp create_project(name) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
      default_branch: "main",
      settings: %{}
    })
  end

  defp setup_product_store do
    store_name = :"run_governance_bridge_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_run_governance_bridge/#{store_name}")

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
