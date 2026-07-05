defmodule JidoCodeWeb.PhaseEighteenIntegrationTest do
  # covers: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.Actor
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project

  test "run detail requires a governed run projection and does not fall back to workflow history",
       %{conn: _conn} do
    register_owner("phase-eighteen-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase-eighteen-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "phase-eighteen-run-detail",
        github_full_name: "owner/phase-eighteen-run-detail",
        default_branch: "main",
        settings: %{}
      })

    run_id = "phase-eighteen-run-detail-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{"source" => "phase_eighteen_test", "mode" => "manual"},
        inputs: %{"task_summary" => "Run detail canonical projection"},
        input_metadata: %{"task_summary" => %{"required" => true, "source" => "test"}},
        initiating_actor: %{id: "owner-1", email: "phase-eighteen-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-04 11:00:00Z]
      })

    {:ok, _view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())
    assert {:ok, %{status: :deleted}} = ProductStore.dispatch(:delete, :run, subject_iri: run_subject_iri(run))

    {:ok, missing_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    assert has_element?(missing_view, "#run-detail-missing-title", "Run not found")
    assert has_element?(missing_view, "#run-detail-missing-detail", run_id)

    {:ok, persisted_workflow_run} =
      WorkflowRun.get_by_project_and_run_id(
        %{project_id: project.id, run_id: run_id},
        actor: Actor.operator_actor()
      )

    assert persisted_workflow_run.id == workflow_run.id
  end

  defp run_subject_iri(run) do
    run.__metadata__
    |> Map.fetch!(:control_plane_record)
    |> Map.fetch!(:subject_iri)
  end
end
