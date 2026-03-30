defmodule JidoCodeWeb.WelcomeLiveTest do
  # covers: baseline.surface.welcome_landing_copy
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "/welcome renders the first-run bootstrap landing when no users exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/welcome")

    assert html =~ "Create your admin account"
  end
end
