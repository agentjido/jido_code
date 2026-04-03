defmodule JidoCodeWeb.PhaseSixIntegrationTest do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.factory_control_plane.compatibility_rollout_backfills_legacy_repo_records
  # covers: architecture.factory_control_plane.compatibility_rollout_exposes_removal_and_rollback_state
  # covers: architecture.run_governance.legacy_workflow_history_backfills_into_governed_runs
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Repo

  test "dashboard, workbench, and run detail preserve mixed-mode continuity while rollout evidence stays explicit",
       %{conn: _conn} do
    register_owner("phase-six-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase-six-owner@example.com", "owner-password-123")

    {legacy_project_id, github_full_name} = insert_legacy_project()
    legacy_run_id = insert_legacy_workflow_run(legacy_project_id)

    {:ok, dashboard_view, _html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(dashboard_view, "#dashboard-compatibility-count-project-gaps", "1")
    assert has_element?(dashboard_view, "#dashboard-compatibility-count-run-gaps", "1")

    assert has_element?(
             dashboard_view,
             "#dashboard-compatibility-rollback-project_projection_recovery",
             "Keep /projects/:id aliases enabled"
           )

    dashboard_view
    |> element("#dashboard-compatibility-refresh")
    |> render_click()

    assert_eventually(fn ->
      has_element?(dashboard_view, "#dashboard-compatibility-count-project-gaps", "0") and
        has_element?(dashboard_view, "#dashboard-compatibility-count-run-gaps", "0")
    end)

    assert has_element?(dashboard_view, "#dashboard-compatibility-backfill-projects", "1")
    assert has_element?(dashboard_view, "#dashboard-compatibility-backfill-workflow-runs", "1")

    {:ok, workbench_view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(workbench_view, "#workbench-project-name-#{legacy_project_id}", github_full_name)

    assert has_element?(
             workbench_view,
             "#workbench-project-issues-project-link-#{legacy_project_id}[href='/projects/#{legacy_project_id}']"
           )

    {:ok, run_view, _html} =
      live(
        recycle(authed_conn),
        "/projects/#{legacy_project_id}/runs/#{legacy_run_id}",
        on_error: :warn
      )

    assert has_element?(run_view, "#run-detail-managed-repo-id")
    assert has_element?(run_view, "#run-detail-current-stage")
    assert has_element?(run_view, "#run-detail-governance-summary")
  end

  defp insert_legacy_project do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    unique = System.unique_integer([:positive])
    project_id = Ecto.UUID.generate()
    project_db_id = Ecto.UUID.dump!(project_id)
    github_full_name = "owner/phase-six-legacy-#{unique}"

    {1, nil} =
      Repo.insert_all("projects", [
        %{
          id: project_db_id,
          name: "phase-six-legacy-#{unique}",
          source_kind: "github",
          source_identifier: github_full_name,
          github_full_name: github_full_name,
          local_path: nil,
          default_branch: "main",
          settings: %{},
          inserted_at: now,
          updated_at: now
        }
      ])

    {project_id, github_full_name}
  end

  defp insert_legacy_workflow_run(project_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    workflow_run_id = Ecto.UUID.dump!(Ecto.UUID.generate())
    project_db_id = Ecto.UUID.dump!(project_id)
    run_id = "phase-six-legacy-run-#{System.unique_integer([:positive])}"

    {1, nil} =
      Repo.insert_all("workflow_runs", [
        %{
          id: workflow_run_id,
          run_id: run_id,
          project_id: project_db_id,
          managed_repo_id: nil,
          workflow_name: "implement_task",
          workflow_version: 1,
          status: "pending",
          trigger: %{"source" => "phase_six_live_test", "mode" => "manual"},
          inputs: %{"task_summary" => "Preserve mixed-mode run detail continuity"},
          input_metadata: %{"task_summary" => %{"required" => true, "source" => "test"}},
          initiating_actor: %{"id" => "operator-live", "email" => "live@example.com"},
          current_step: "queued",
          status_transitions: [],
          step_results: %{},
          error: nil,
          started_at: now,
          completed_at: nil,
          retry_of_run_id: nil,
          retry_attempt: 1,
          retry_lineage: [],
          inserted_at: now,
          updated_at: now
        }
      ])

    run_id
  end

  defp assert_eventually(assertion_fun, attempts \\ 20)

  defp assert_eventually(assertion_fun, attempts) when attempts > 0 do
    if assertion_fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(assertion_fun, attempts - 1)
    end
  end

  defp assert_eventually(_assertion_fun, 0) do
    flunk("expected condition to become true")
  end
end
