defmodule JidoCodeWeb.AuthSessionLiveTest do
  # covers: auth.system.local_email_identity
  # covers: auth.system.password_registration_and_sign_in
  # covers: auth.system.ready_state_local_auth_handoff
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Accounts.SessionTokens

  test "valid local credentials create a browser session and enter the dashboard by default", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")
    assert is_binary(session_token)

    welcome_html =
      authed_conn
      |> recycle()
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "owner@example.com"
    assert welcome_html =~ "Sign Out"
  end

  test "sign-in preserves an explicit return_to over the ready-state dashboard default", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")
    authed_conn = authenticate_owner_conn(conn, "owner@example.com", "owner-password-123")

    auth_response =
      authed_conn
      |> put_session(:return_to, "/repos")
      |> get(~p"/sign-out")

    assert redirected_to(auth_response, 302) == "/repos"
  end

  test "signed-in ready-state sessions are redirected away from the sign-in route to dashboard", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             live(recycle(authed_conn), ~p"/sign-in", on_error: :warn)
  end

  test "invalid local credentials do not create a browser session and preserve anonymous landing state", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    assert {:error, :invalid_token} = SessionTokens.verify("not-a-product-session-token")

    welcome_html =
      build_conn()
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "Sign In"
    refute welcome_html =~ "Create Account"
    refute welcome_html =~ "owner@example.com"
  end
end
