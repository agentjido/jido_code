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

    on_exit(fn ->
      case original_target do
        nil -> System.delete_env("BURRITO_TARGET")
        value -> System.put_env("BURRITO_TARGET", value)
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

  test "landing page exposes sign-in and GitHub login once a local user already exists", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")
    enable_provider_login!(:github, "github.com")

    {:ok, view, _html} = live(conn, ~p"/welcome")

    assert has_element?(
             view,
             ~s|a[href="/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome"]|,
             "Sign In with GitHub"
           )

    assert has_element?(view, "a", "Sign In")
    refute has_element?(view, "a", "Create Account")
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
end
