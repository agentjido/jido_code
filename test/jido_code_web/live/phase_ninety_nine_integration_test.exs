defmodule JidoCodeWeb.PhaseNinetyNineIntegrationTest do
  # covers: architecture.frontend_stack.root_area_shell_owns_navigation
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)

    Application.put_env(:jido_code, :system_config_loader, fn ->
      {:ok,
       %{
         onboarding_completed: true,
         onboarding_step: 8,
         onboarding_state: %{},
         default_environment: :sprite,
         workspace_root: nil
       }}
    end)

    on_exit(fn ->
      restore_env(:system_config_loader, original_loader)
    end)

    register_owner("phase99-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase99-owner@example.com", "owner-password-123")

    {:ok, authed_conn: authed_conn}
  end

  test "99.4.1 root area routes share the area shell, status strip, and overview panel", %{
    authed_conn: authed_conn
  } do
    for {path, area_id, label} <- [
          {"/dashboard", "dashboard", "Dashboard"},
          {"/repos", "repositories", "Repositories"},
          {"/workbench", "workbench", "Workbench"},
          {"/conversations", "conversations", "Conversations"},
          {"/workflows", "workflows", "Workflows"},
          {"/agents", "agents", "Agents"},
          {"/memory", "memory", "Memory"},
          {"/semantic", "semantic", "Semantic"},
          {"/settings", "settings", "Settings"}
        ] do
      {:ok, view, _html} = live(recycle(authed_conn), path, on_error: :warn)

      assert has_element?(view, "#operator-app-shell[data-active-area='#{area_id}']")
      assert has_element?(view, "#operator-area-menu-#{area_id}[aria-current='page']")
      assert has_element?(view, "#operator-shell-title", label)
      assert has_element?(view, "#operator-status-area", "Area: #{label}")
      assert has_element?(view, "#operator-status-connection", "Connection: connected")
      assert has_element?(view, "#area-overview-panel-#{area_id}")
    end
  end

  test "99.4.2 public and detail route gates stay intact", %{conn: conn, authed_conn: authed_conn} do
    assert redirected_to(get(conn, ~p"/"), 302) == "/welcome"
    assert_live_redirect(live(recycle(conn), ~p"/semantic", on_error: :warn), "/welcome")

    %{route_id: route_id} =
      provision_managed_repo!(%{
        name: "phase99-detail-repo",
        github_full_name: "owner/phase99-detail-repo",
        default_branch: "main",
        settings: %{}
      })

    {:ok, repo_view, _html} = live(recycle(authed_conn), ~p"/repos/#{route_id}", on_error: :warn)

    assert has_element?(repo_view, "#operator-app-shell[data-active-area='repositories']")
    assert has_element?(repo_view, "#operator-area-menu-repositories[aria-current='page']")
    refute has_element?(repo_view, "#area-overview-panel-repositories")
    assert has_element?(repo_view, "#project-detail-title", "Managed repo detail")
  end

  defp assert_live_redirect({:error, {:redirect, %{to: path}}}, expected) when path == expected,
    do: :ok

  defp assert_live_redirect({:error, {:live_redirect, %{to: path}}}, expected)
       when path == expected,
       do: :ok

  defp assert_live_redirect(other, expected) do
    flunk("expected live redirect to #{expected}, got: #{inspect(other)}")
  end
end
