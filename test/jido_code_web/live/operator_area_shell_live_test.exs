defmodule JidoCodeWeb.OperatorAreaShellLiveTest do
  # covers: architecture.frontend_stack.root_area_shell_owns_navigation
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "shared area shell renders consistent selected states across major signed-in routes",
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

    assert_area_shell(dashboard_view, "dashboard", "Dashboard", "Operational home and next actions")
    assert has_element?(dashboard_view, "#area-overview-panel-dashboard")
    assert has_element?(dashboard_view, "#operator-area-menu-workbench")
    assert has_element?(dashboard_view, "#operator-area-menu-conversations")
    refute has_element?(dashboard_view, "#operator-global-nav")
    refute has_element?(dashboard_view, "#operator-context-nav")

    {:ok, workbench_view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert_area_shell(workbench_view, "workbench", "Workbench", "Dense specialist workspace")
    assert has_element?(workbench_view, "#area-overview-panel-workbench")
    refute has_element?(workbench_view, "#operator-global-nav")
    refute has_element?(workbench_view, "#operator-context-nav")

    {:ok, settings_view, _html} = live(recycle(authed_conn), ~p"/settings", on_error: :warn)

    assert_area_shell(settings_view, "settings", "Settings", "Auth, integrations, and runtime defaults")
    assert has_element?(settings_view, "#area-overview-panel-settings")
    refute has_element?(settings_view, "#operator-context-settings-tab")

    settings_view
    |> element("#settings-github-open-add-modal")
    |> render_click()

    assert has_element?(
             settings_view,
             "#add-repo-modal[role='dialog'][aria-modal='true'][aria-labelledby='add-repo-modal-title']"
           )

    assert has_element?(settings_view, "#add-repo-modal-title", "Add GitHub Repository")

    {:ok, repo_view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert_area_shell(repo_view, "repositories", "Repositories", "Managed repositories and detail context")
    refute has_element?(repo_view, "#area-overview-panel-repositories")
    refute has_element?(repo_view, "#operator-context-repo")

    {:ok, run_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    assert_area_shell(run_view, "repositories", "Repositories", "Managed repositories and detail context")
    refute has_element?(run_view, "#area-overview-panel-repositories")
    refute has_element?(run_view, "#operator-context-run")
  end

  test "detail routes stay in repositories while preserving route-owned return links",
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

    assert_area_shell(dashboard_repo_view, "repositories", "Repositories", "Managed repositories and detail context")

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

    assert_area_shell(workbench_repo_view, "repositories", "Repositories", "Managed repositories and detail context")
    assert has_element?(workbench_repo_view, "#project-detail-breadcrumb-return[href='/workbench']", "Workbench")

    {:ok, workbench_run_view, _html} =
      live(
        recycle(authed_conn),
        "/repos/#{project.id}/runs/#{run_id}?return_to=#{encoded_workbench_return_to}",
        on_error: :warn
      )

    assert_area_shell(workbench_run_view, "repositories", "Repositories", "Managed repositories and detail context")

    assert has_element?(
             workbench_run_view,
             "#run-detail-breadcrumb-repo[href='/repos/#{project.id}?return_to=#{encoded_workbench_return_to}']"
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

    assert_route_pane_shell(workbench_view, "workbench-shell", "workbench-pane")
    assert has_element?(workbench_view, "#workbench-return-dashboard")
    assert has_element?(workbench_view, "#workbench-apply-filters[form='workbench-filters-form']")
    refute has_element?(workbench_view, "#workbench-nav")

    {:ok, inventory_view, _html} = live(recycle(authed_conn), ~p"/repos", on_error: :warn)

    assert_area_shell(inventory_view, "repositories", "Repositories", "Managed repositories and detail context")
    assert has_element?(inventory_view, "#area-overview-panel-repositories")
    assert_route_pane_shell(inventory_view, "project-inventory-shell", "project-inventory-pane")
    assert has_element?(inventory_view, "#project-inventory-reset-filters[href='/repos']")

    assert has_element?(
             inventory_view,
             "#project-inventory-apply-filters[form='project-inventory-filters-form']"
           )

    refute has_element?(inventory_view, "#project-inventory-nav")

    {:ok, workflows_view, _html} = live(recycle(authed_conn), ~p"/workflows", on_error: :warn)

    assert_area_shell(workflows_view, "workflows", "Workflows", "Governed run launch and history")
    assert has_element?(workflows_view, "#area-overview-panel-workflows")
    assert_route_pane_shell(workflows_view, "workflows-shell", "workflows-pane")
    assert has_element?(workflows_view, "#workflows-start-run")
    refute has_element?(workflows_view, "#workflows-nav")

    {:ok, agents_view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert_area_shell(agents_view, "agents", "Agents", "Repo-scoped support automation")
    assert has_element?(agents_view, "#area-overview-panel-agents")
    assert_route_pane_shell(agents_view, "agents-shell", "agents-pane")
    assert has_element?(agents_view, "#agents-project-table")
    refute has_element?(agents_view, "#agents-nav")

    {:ok, settings_view, _html} = live(recycle(authed_conn), ~p"/settings/auth", on_error: :warn)

    assert has_element?(settings_view, "#settings-shell")
    assert has_element?(settings_view, "#settings-shell-breadcrumbs")
    refute has_element?(settings_view, "#settings-shell-section-groups")
    assert has_element?(settings_view, "#settings-nav-auth[aria-current='page']", "Auth & Integrations")
    assert has_element?(settings_view, "#settings-pane-auth")
    assert has_element?(settings_view, "#settings-pane-auth-middle")
    assert has_element?(settings_view, "#settings-pane-auth-footer")
    assert has_element?(settings_view, "#settings-auth-refresh-github-service-checks")
    assert_area_shell(settings_view, "settings", "Settings", "Auth, integrations, and runtime defaults")

    settings_view
    |> element("#settings-nav-security")
    |> render_click()

    assert_patch(settings_view, "/settings/security")
    assert has_element?(settings_view, "#settings-nav-security[aria-current='page']", "Security")
    assert has_element?(settings_view, "#settings-pane-security")
    assert has_element?(settings_view, "#settings-pane-security-middle")
    refute has_element?(settings_view, "#settings-pane-security-footer")
    refute has_element?(settings_view, "#settings-auth-refresh-github-service-checks")
    assert_area_shell(settings_view, "settings", "Settings", "Auth, integrations, and runtime defaults")

    {:ok, run_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    assert_route_pane_shell(run_view, "run-detail-shell", "run-detail")
    assert has_element?(run_view, "#run-detail-breadcrumb-parent[href='/repos']", "Repositories")

    assert has_element?(
             run_view,
             "#run-detail-breadcrumb-repo[href='/repos/#{project.id}?return_to=#{URI.encode_www_form("/repos")}']"
           )

    assert has_element?(run_view, "#run-detail-breadcrumb-current", "Run #{run_id}")
    assert has_element?(run_view, "#run-detail-return-link[href='/repos/#{project.id}']", "Back to Repo detail")
  end

  defp assert_route_pane_shell(view, shell_id, pane_id) do
    assert has_element?(view, "##{shell_id}")
    assert has_element?(view, "##{shell_id}-breadcrumbs")
    refute has_element?(view, "##{shell_id}-section-groups")
    assert has_element?(view, "##{pane_id}")
    assert has_element?(view, "##{pane_id}-header")
    assert has_element?(view, "##{pane_id}-middle")
  end

  defp assert_area_shell(view, area_id, label, subtitle) do
    assert has_element?(view, "#operator-app-shell[data-active-area='#{area_id}']")
    assert has_element?(view, "#operator-shell-title", label)
    assert has_element?(view, "#operator-shell-subtitle", subtitle)
    assert has_element?(view, "#operator-area-menu[aria-label='Product areas']")
    assert has_element?(view, "#operator-area-menu-#{area_id}[aria-current='page']")
    assert has_element?(view, "#operator-status-strip[role='status'][aria-live='polite']")
    assert has_element?(view, "#operator-status-area", "Area: #{label}")
    assert has_element?(view, "#operator-status-connection", "Connection: connected")
  end
end
