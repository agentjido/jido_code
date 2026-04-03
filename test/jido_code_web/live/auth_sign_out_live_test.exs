defmodule JidoCodeWeb.AuthSignOutLiveTest do
  # covers: auth.system.revocable_credentials
  use JidoCodeWeb.ConnCase, async: false

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
    refute welcome_html =~ "Create Account"
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
end
