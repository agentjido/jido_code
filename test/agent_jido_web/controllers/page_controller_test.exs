defmodule AgentJidoWeb.PageControllerTest do
  use AgentJidoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Agent Jido"
  end
end
