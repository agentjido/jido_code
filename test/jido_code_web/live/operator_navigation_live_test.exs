defmodule JidoCodeWeb.OperatorNavigationLiveTest do
  # covers: architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding
  # covers: architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "shared operator navigation renders consistent selected states and context across major signed-in routes",
       %{conn: _conn} do
    register_owner("operator-nav-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("operator-nav-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-operator-navigation",
        github_full_name: "owner/repo-operator-navigation",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-operator-navigation-#{System.unique_integer([:positive])}"

    {:ok, _run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Verify global navigation route coverage"},
        input_metadata: %{"task_summary" => %{required: true, source: "test"}},
        initiating_actor: %{id: "owner-1", email: "operator-nav-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-28 12:00:00Z]
      })

    {:ok, dashboard_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?subject=work&section=overview", on_error: :warn)

    assert has_element?(dashboard_view, "#operator-global-nav-dashboard[aria-current='page']")
    assert has_element?(dashboard_view, "#operator-global-nav-workbench")
    assert has_element?(dashboard_view, "#operator-global-nav-repositories")
    assert has_element?(dashboard_view, "#operator-route-badge", "Authenticated home")
    assert has_element?(dashboard_view, "#operator-route-label", "Dashboard")
    refute has_element?(dashboard_view, "#operator-context-nav")

    {:ok, workbench_view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(workbench_view, "#operator-global-nav-workbench[aria-current='page']")
    assert has_element?(workbench_view, "#operator-route-badge", "Specialist inventory")
    assert has_element?(workbench_view, "#operator-route-label", "Workbench")
    refute has_element?(workbench_view, "#operator-context-nav")

    {:ok, settings_view, _html} = live(recycle(authed_conn), ~p"/settings/auth", on_error: :warn)

    assert has_element?(settings_view, "#operator-global-nav-settings[aria-current='page']")
    assert has_element?(settings_view, "#operator-route-badge", "Operator configuration")
    assert has_element?(settings_view, "#operator-route-label", "Settings")
    assert has_element?(settings_view, "#operator-context-settings-tab[aria-current='page']", "Auth & Integrations")

    {:ok, repo_view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(repo_view, "#operator-global-nav-repositories[aria-current='page']")
    assert has_element?(repo_view, "#operator-route-badge", "Managed repo")
    assert has_element?(repo_view, "#operator-route-label", "owner/repo-operator-navigation")
    assert has_element?(repo_view, "#operator-context-repo[aria-current='page']", "owner/repo-operator-navigation")

    {:ok, run_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    assert has_element?(run_view, "#operator-global-nav-repositories[aria-current='page']")
    assert has_element?(run_view, "#operator-route-badge", "Governed run")
    assert has_element?(run_view, "#operator-route-label", "Run #{run_id}")

    assert has_element?(
             run_view,
             "#operator-context-repo[href='/repos/#{project.id}?return_to=#{URI.encode_www_form("/repos")}']"
           )

    assert has_element?(run_view, "#operator-context-run[aria-current='page']", "Run #{run_id}")
  end

  test "repo and run detail preserve the broader selected major destination from explicit parent surfaces",
       %{conn: _conn} do
    register_owner("operator-nav-parent-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("operator-nav-parent-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-operator-parent",
        github_full_name: "owner/repo-operator-parent",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-operator-parent-#{System.unique_integer([:positive])}"

    {:ok, _run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Verify parent-surface selection"},
        input_metadata: %{"task_summary" => %{required: true, source: "test"}},
        initiating_actor: %{id: "owner-1", email: "operator-nav-parent-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-28 12:30:00Z]
      })

    dashboard_return_to = "/dashboard?subject=work&section=overview"
    encoded_dashboard_return_to = URI.encode_www_form(dashboard_return_to)

    {:ok, dashboard_repo_view, _html} =
      live(
        recycle(authed_conn),
        "/repos/#{project.id}?return_to=#{encoded_dashboard_return_to}",
        on_error: :warn
      )

    assert has_element?(dashboard_repo_view, "#operator-global-nav-dashboard[aria-current='page']")

    assert has_element?(
             dashboard_repo_view,
             "#project-detail-breadcrumb-return[href='#{dashboard_return_to}']",
             "Dashboard"
           )

    workbench_return_to = "/workbench"
    encoded_workbench_return_to = URI.encode_www_form(workbench_return_to)

    {:ok, workbench_repo_view, _html} =
      live(
        recycle(authed_conn),
        "/repos/#{project.id}?return_to=#{encoded_workbench_return_to}",
        on_error: :warn
      )

    assert has_element?(workbench_repo_view, "#operator-global-nav-workbench[aria-current='page']")
    assert has_element?(workbench_repo_view, "#project-detail-breadcrumb-return[href='/workbench']", "Workbench")

    {:ok, workbench_run_view, _html} =
      live(
        recycle(authed_conn),
        "/repos/#{project.id}/runs/#{run_id}?return_to=#{encoded_workbench_return_to}",
        on_error: :warn
      )

    assert has_element?(workbench_run_view, "#operator-global-nav-workbench[aria-current='page']")

    assert has_element?(
             workbench_run_view,
             "#operator-context-repo[href='/repos/#{project.id}?return_to=#{encoded_workbench_return_to}']"
           )
  end
end
