defmodule JidoCodeWeb.AuthBoundaryLiveTest do
  # covers: auth.system.revocable_credentials
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.TokenResource.Actions
  alias JidoCode.Accounts.Token

  test "anonymous landing requests stay anonymous", %{conn: conn} do
    welcome_html =
      conn
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "Create your admin account"
    refute welcome_html =~ "Sign Out"
  end

  test "authenticated local sessions render signed-in landing state", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")
    assert is_binary(session_token)

    welcome_html =
      authed_conn
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "owner@example.com"
    assert welcome_html =~ "Sign Out"
  end

  test "revoked local sessions fall back to anonymous landing state and clear the stale session", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")
    assert is_binary(session_token)
    assert :ok = Actions.revoke(Token, session_token)

    response =
      authed_conn
      |> recycle()
      |> get(~p"/welcome")

    welcome_html = html_response(response, 200)

    assert welcome_html =~ "Sign In"
    refute welcome_html =~ "Create Account"
    refute welcome_html =~ "owner@example.com"
    refute welcome_html =~ "Sign Out"
    assert get_session(response, "user_token") == nil
  end
end
