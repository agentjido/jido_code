defmodule JidoCodeWeb.HomeLiveTest do
  # covers: baseline.surface.auth_entrypoints_visible
  # covers: baseline.surface.welcome_landing_copy
  # covers: setup.onboarding.deployment_mode_auto_detected
  # covers: auth.provider_login_flow.entrypoint_visible
  # covers: auth.provider_login_flow.local_auth_fallback_visible
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AuthProviders.ProviderConfig

  setup do
    original_target = System.get_env("BURRITO_TARGET")
    original_prerequisite_checker = Application.get_env(:jido_code, :setup_prerequisite_checker, :__missing__)
    original_prerequisite_timeout_ms =
      Application.get_env(:jido_code, :setup_prerequisite_timeout_ms, :__missing__)

    on_exit(fn ->
      case original_target do
        nil -> System.delete_env("BURRITO_TARGET")
        value -> System.put_env("BURRITO_TARGET", value)
      end

      case original_prerequisite_checker do
        :__missing__ -> Application.delete_env(:jido_code, :setup_prerequisite_checker)
        value -> Application.put_env(:jido_code, :setup_prerequisite_checker, value)
      end

      case original_prerequisite_timeout_ms do
        :__missing__ -> Application.delete_env(:jido_code, :setup_prerequisite_timeout_ms)
        value -> Application.put_env(:jido_code, :setup_prerequisite_timeout_ms, value)
      end
    end)

    :ok
  end

  test "landing page opens first-run bootstrap when no users exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/welcome")

    assert html =~ "Create your admin account"
    assert html =~ "Checking your system"
    refute html =~ "Sign In with GitHub"
  end

  test "landing page hides provider login during bootstrap even when GitHub login is configured", %{conn: conn} do
    enable_provider_login!(:github, "github.com")

    {:ok, _view, html} = live(conn, ~p"/welcome")

    refute html =~ "Sign In with GitHub"
    refute html =~ "Create Account"
  end

  test "landing page uses desktop bootstrap copy when deployment mode auto-detects desktop", %{conn: conn} do
    System.put_env("BURRITO_TARGET", "darwin-aarch64")

    {:ok, _view, html} = live(conn, ~p"/welcome")

    assert html =~ "brand-new desktop install"
  end

  test "landing page settles to a timeout state when prerequisite checking hangs", %{conn: conn} do
    Application.put_env(:jido_code, :setup_prerequisite_timeout_ms, 25)

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      Process.sleep(200)

      %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        status: :pass,
        checks: []
      }
    end)

    {:ok, view, _html} = live(conn, ~p"/welcome")

    assert_eventually(fn ->
      rendered = render(view)

      assert rendered =~ "Some checks timed out. Your system may not be fully ready."
      assert rendered =~ "Complete system check first"
      refute rendered =~ "Checking your system…"
    end)
  end

  test "landing page exposes sign-in and GitHub login once a local user already exists", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")
    enable_provider_login!(:github, "github.com")

    {:ok, view, _html} = live(conn, ~p"/welcome")

    assert has_element?(
             view,
             ~s|a[href="/auth/providers/github/start?provider_host=github.com"]|,
             "Sign In with GitHub"
           )

    assert has_element?(view, "a", "Sign In")
    refute has_element?(view, "a", "Create Account")
  end

  test "signed-in ready-state welcome stays a compact dashboard and settings handoff",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} = authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(view, "#welcome-open-dashboard", "Open Dashboard")
    assert has_element?(view, "#welcome-open-settings", "Open Auth & Integrations")
    assert has_element?(
             view,
             "#welcome-ready-handoff-note",
             "Dashboard is the default authenticated entry"
           )
    refute has_element?(view, "#welcome-operator-settings-handoff")

    refute html =~
             "Product routes, demos, setup flows, APIs, and workbench surfaces are commented out until the new spec-led baseline is validated."
  end

  defp enable_provider_login!(provider, provider_host) do
    {:ok, config} =
      ProviderConfig.upsert(
        %{
          provider: provider,
          provider_host: provider_host,
          enabled: true,
          login_enabled: true,
          broker_issuer: "https://broker.example.com",
          broker_audience: "jido-code",
          broker_base_url: "https://broker.example.com"
        },
        authorize?: false
      )

    config
  end

  defp assert_eventually(assertion_fun, attempts \\ 20)

  defp assert_eventually(assertion_fun, attempts) when attempts > 0 do
    assertion_fun.()
  rescue
    error in [ExUnit.AssertionError] ->
      if attempts == 1 do
        reraise error, __STACKTRACE__
      else
        Process.sleep(25)
        assert_eventually(assertion_fun, attempts - 1)
      end
  end
end
