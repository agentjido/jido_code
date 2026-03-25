defmodule JidoCodeWeb.WelcomeLiveTest do
  # covers: baseline.surface.welcome_landing_copy
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "/welcome renders the operator landing page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/welcome")

    assert html =~ "Welcome to Jido Code"
  end
end
