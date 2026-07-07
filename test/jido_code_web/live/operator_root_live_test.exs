defmodule JidoCodeWeb.OperatorRootLiveTest do
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.root_area_shell_owns_navigation
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

    register_owner("operator-root-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("operator-root-owner@example.com", "owner-password-123")

    {:ok, authed_conn: authed_conn}
  end

  test "new root area paths enter the operator root shell", %{authed_conn: authed_conn} do
    for {path, area_id, label} <- [
          {"/conversations", "conversations", "Conversations"},
          {"/memory", "memory", "Memory"},
          {"/semantic", "semantic", "Semantic"}
        ] do
      {:ok, view, _html} = live(recycle(authed_conn), path, on_error: :warn)

      assert has_element?(view, "#operator-root-shell[data-active-area='#{area_id}']")
      assert has_element?(view, "#operator-root-title", label)
      assert has_element?(view, "#operator-global-nav-#{area_id}[aria-current='page']")
      assert has_element?(view, "#operator-root-route-#{area_id}[aria-current='page']")
    end
  end

  test "root handoff keeps anonymous users public and sends ready signed-in users to dashboard", %{
    conn: conn,
    authed_conn: authed_conn
  } do
    assert redirected_to(get(conn, ~p"/"), 302) == "/welcome"
    assert redirected_to(get(authed_conn, ~p"/"), 302) == "/dashboard"
  end

  test "new root area paths keep the authenticated live route gate", %{conn: conn} do
    for path <- ["/conversations", "/memory", "/semantic"] do
      assert_live_redirect(live(recycle(conn), path, on_error: :warn), "/welcome")
    end
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
