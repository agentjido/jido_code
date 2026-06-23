defmodule JidoCodeWeb.FrontendResetLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "public route renders the reset frontend surface", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/welcome")

    assert html =~ ~s|id="jido-code-reset-surface"|
    assert html =~ "Welcome"
    assert html =~ "previous UI component"
  end

  test "authenticated product routes render reset surfaces", %{conn: _conn} do
    conn = authenticated_owner_conn()

    for {path, title} <- [
          {~p"/dashboard", "Dashboard"},
          {~p"/workbench", "Workbench"},
          {~p"/workflows", "Workflows"},
          {~p"/agents", "Agents"},
          {~p"/repos", "Repositories"},
          {~p"/settings", "Settings"}
        ] do
      {:ok, _view, html} = live(recycle(conn), path)

      assert html =~ ~s|id="jido-code-reset-surface"|
      assert html =~ title
    end
  end

  defp authenticated_owner_conn do
    unique_suffix = System.unique_integer([:positive])
    email = "frontend-reset-owner-#{unique_suffix}@example.com"
    password = "owner-password-123"

    register_owner(email, password)

    build_conn()
    |> authenticate_owner_conn(email, password)
  end
end
