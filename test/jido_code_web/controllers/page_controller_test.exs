defmodule JidoCodeWeb.PageControllerTest do
  # covers: baseline.surface.root_redirects_to_welcome
  use JidoCodeWeb.ConnCase

  test "GET / redirects to welcome when onboarding is incomplete", %{conn: conn} do
    conn = get(conn, ~p"/")

    redirect_to = redirected_to(conn)
    uri = URI.parse(redirect_to)

    assert uri.path == "/welcome"
    assert uri.query in [nil, ""]
  end
end
