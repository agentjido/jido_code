defmodule JidoCodeWeb.AuthSignOutLiveTest do
  # covers: auth.system.revocable_credentials
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User

  test "sign out clears browser session credentials and restores anonymous landing state", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")
    assert is_binary(session_token)

    sign_out_response = get(authed_conn, ~p"/sign-out")

    assert redirected_to(sign_out_response, 302) == "/"
    assert Phoenix.Flash.get(sign_out_response.assigns.flash, :info) == "You are now signed out"
    assert get_session(sign_out_response, "user_token") == nil

    welcome_html =
      sign_out_response
      |> recycle()
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "Sign In"
    assert welcome_html =~ "Create Account"
    refute welcome_html =~ "owner@example.com"
  end

  test "failed session invalidation provides retry guidance and keeps session unchanged", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    {authed_conn, session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")
    assert is_binary(session_token)

    previous_invalidator = Application.get_env(:jido_code, :sign_out_invalidator)

    on_exit(fn ->
      restore_sign_out_invalidator(previous_invalidator)
    end)

    Application.put_env(:jido_code, :sign_out_invalidator, fn _conn, _otp_app ->
      {:error, :forced_invalidation_failure}
    end)

    sign_out_response = get(authed_conn, ~p"/sign-out")

    assert redirected_to(sign_out_response, 302) == "/"

    assert Phoenix.Flash.get(sign_out_response.assigns.flash, :error) ==
             "Sign-out could not complete. Please retry; your current session is still active."

    assert get_session(sign_out_response, "user_token") == session_token

    welcome_html =
      sign_out_response
      |> recycle()
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "owner@example.com"
    assert welcome_html =~ "Sign Out"
  end

  defp restore_sign_out_invalidator(nil), do: Application.delete_env(:jido_code, :sign_out_invalidator)

  defp restore_sign_out_invalidator(invalidator),
    do: Application.put_env(:jido_code, :sign_out_invalidator, invalidator)

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
