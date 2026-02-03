defmodule AgentJidoWeb.Demos.ChatLiveTest do
  use AgentJidoWeb.ConnCase, async: false

  describe "ChatLive" do
    @tag :skip
    test "renders chat interface when authenticated", %{conn: _conn} do
      # This test requires authentication - skip for now until auth helpers are set up
      # When auth is available:
      # conn = log_in_user(conn, user)
      # {:ok, view, html} = live(conn, ~p"/demos/chat")

      # assert has_element?(view, "#chat-messages")
      # assert has_element?(view, "#chat-form")
      # assert has_element?(view, "#chat-input")
      # assert html =~ "AI Chat Agent Demo"
      # assert html =~ "Start a conversation"
    end

    @tag :skip
    test "sending a message adds it to the messages list", %{conn: _conn} do
      # Requires authenticated user and agent infrastructure
      # {:ok, view, _html} = live(conn, ~p"/demos/chat")

      # view
      # |> form("#chat-form", input: "What is 2 + 2?")
      # |> render_submit()

      # assert has_element?(view, "#chat-messages", "What is 2 + 2?")
    end
  end
end
