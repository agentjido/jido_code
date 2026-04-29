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

  test "adjacent signed-in routes reuse proportional shells and keep route-owned local navigation",
       %{conn: _conn} do
    register_owner("operator-nav-adjacent-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("operator-nav-adjacent-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-operator-adjacent",
        github_full_name: "owner/repo-operator-adjacent",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-operator-adjacent-#{System.unique_integer([:positive])}"

    {:ok, _run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Verify adjacent route shell contracts"},
        input_metadata: %{"task_summary" => %{required: true, source: "test"}},
        initiating_actor: %{id: "owner-1", email: "operator-nav-adjacent-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-28 13:00:00Z]
      })

    {:ok, workbench_view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert_single_pane_shell(workbench_view, "workbench-shell", "workbench-pane")
    assert has_element?(workbench_view, "#workbench-return-dashboard")
    assert has_element?(workbench_view, "#workbench-apply-filters[form='workbench-filters-form']")
    refute has_element?(workbench_view, "#workbench-nav")

    {:ok, inventory_view, _html} = live(recycle(authed_conn), ~p"/repos", on_error: :warn)

    assert_single_pane_shell(inventory_view, "project-inventory-shell", "project-inventory-pane")
    assert has_element?(inventory_view, "#project-inventory-reset-filters[href='/repos']")

    assert has_element?(
             inventory_view,
             "#project-inventory-apply-filters[form='project-inventory-filters-form']"
           )

    refute has_element?(inventory_view, "#project-inventory-nav")

    {:ok, workflows_view, _html} = live(recycle(authed_conn), ~p"/workflows", on_error: :warn)

    assert_single_pane_shell(workflows_view, "workflows-shell", "workflows-pane")
    assert has_element?(workflows_view, "#workflows-start-run")
    refute has_element?(workflows_view, "#workflows-nav")

    {:ok, agents_view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert_single_pane_shell(agents_view, "agents-shell", "agents-pane")
    assert has_element?(agents_view, "#agents-project-table")
    refute has_element?(agents_view, "#agents-nav")

    {:ok, settings_view, _html} = live(recycle(authed_conn), ~p"/settings/auth", on_error: :warn)

    assert has_element?(settings_view, "#settings-shell")
    assert has_element?(settings_view, "#settings-shell-breadcrumbs")
    refute has_element?(settings_view, "#settings-shell-parent-subjects")
    assert has_element?(settings_view, "#settings-nav-auth[aria-current='page']", "Auth & Integrations")
    assert has_element?(settings_view, "#settings-pane-auth")
    assert has_element?(settings_view, "#settings-pane-auth-middle")
    assert has_element?(settings_view, "#settings-pane-auth-footer")
    assert has_element?(settings_view, "#settings-auth-refresh-github-service-checks")
    assert has_element?(settings_view, "#operator-context-settings-tab[aria-current='page']", "Auth & Integrations")

    settings_view
    |> element("#settings-nav-security")
    |> render_click()

    assert_patch(settings_view, "/settings/security")
    assert has_element?(settings_view, "#settings-nav-security[aria-current='page']", "Security")
    assert has_element?(settings_view, "#settings-pane-security")
    assert has_element?(settings_view, "#settings-pane-security-middle")
    refute has_element?(settings_view, "#settings-pane-security-footer")
    refute has_element?(settings_view, "#settings-auth-refresh-github-service-checks")
    assert has_element?(settings_view, "#operator-context-settings-tab[aria-current='page']", "Security settings")

    {:ok, run_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    assert_single_pane_shell(run_view, "run-detail-shell", "run-detail")
    assert has_element?(run_view, "#run-detail-breadcrumb-parent[href='/repos']", "Repositories")

    assert has_element?(
             run_view,
             "#run-detail-breadcrumb-repo[href='/repos/#{project.id}?return_to=#{URI.encode_www_form("/repos")}']"
           )

    assert has_element?(run_view, "#run-detail-breadcrumb-current", "Run #{run_id}")
    assert has_element?(run_view, "#run-detail-return-link[href='/repos/#{project.id}']", "Back to Repo detail")
  end

  defp assert_single_pane_shell(view, shell_id, pane_id) do
    assert has_element?(view, "##{shell_id}")
    assert has_element?(view, "##{shell_id}-breadcrumbs")
    refute has_element?(view, "##{shell_id}-parent-subjects")
    assert has_element?(view, "##{pane_id}")
    assert has_element?(view, "##{pane_id}-header")
    assert has_element?(view, "##{pane_id}-middle")
  end
end
