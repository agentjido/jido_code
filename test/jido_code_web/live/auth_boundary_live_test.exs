defmodule JidoCodeWeb.AuthBoundaryLiveTest do
  # covers: auth.system.revocable_credentials
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias AshAuthentication.TokenResource.Actions
  alias JidoCode.Accounts.Token
  alias JidoCode.Accounts.User

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

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, _owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    :ok
  end

  defp authenticate_owner_conn(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response = build_conn() |> get(owner_sign_in_with_token_path(strategy, token))
    assert redirected_to(auth_response, 302) == "/"
    session_token = get_session(auth_response, "user_token")
    assert is_binary(session_token)
    {recycle(auth_response), session_token}
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end
end
