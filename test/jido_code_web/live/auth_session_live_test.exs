defmodule JidoCodeWeb.AuthSessionLiveTest do
  # covers: auth.system.local_email_identity
  # covers: auth.system.password_registration_and_sign_in
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User

  test "valid local credentials create a browser session and render signed-in landing state", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {:ok, sign_in_view, _html} = live(conn, ~p"/sign-in", on_error: :warn)

    sign_in_view
    |> form("form[action='/auth/user/password/sign_in']", %{
      "user" => %{"email" => "owner@example.com", "password" => "owner-password-123"}
    })
    |> render_submit()

    auth_redirect_path =
      sign_in_view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/"

    session_token = get_session(auth_response, "user_token")
    assert is_binary(session_token)

    welcome_html =
      auth_response
      |> recycle()
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "owner@example.com"
    assert welcome_html =~ "Sign Out"
  end

  test "invalid local credentials do not create a browser session and preserve anonymous landing state", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")
    strategy = Info.strategy!(User, :password)

    assert {:error, %AshAuthentication.Errors.AuthenticationFailed{} = auth_error} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "wrong-password-123"},
               context: %{token_type: :sign_in}
             )

    assert match?(%AshAuthentication.Strategy.Password{}, auth_error.strategy)

    {:ok, sign_in_view, _html} = live(conn, ~p"/sign-in", on_error: :warn)

    sign_in_view
    |> form("form[action='/auth/user/password/sign_in']", %{
      "user" => %{"email" => "owner@example.com", "password" => "wrong-password-123"}
    })
    |> render_submit()

    :ok = refute_redirected(sign_in_view)
    assert render(sign_in_view) =~ "Email or password was incorrect"

    welcome_html =
      build_conn()
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "Sign In"
    refute welcome_html =~ "Create Account"
    refute welcome_html =~ "owner@example.com"
  end

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path
end
