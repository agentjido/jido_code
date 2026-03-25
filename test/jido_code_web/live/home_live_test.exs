defmodule JidoCodeWeb.HomeLiveTest do
  # covers: baseline.surface.auth_entrypoints_visible
  # covers: baseline.surface.welcome_landing_copy
  # covers: auth.provider_login_flow.entrypoint_visible
  # covers: auth.provider_login_flow.local_auth_fallback_visible
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AuthProviders.ProviderConfig

  test "landing page keeps local auth visible when GitHub provider login is not configured", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/welcome")

    assert html =~ "Sign In"
    assert html =~ "Create Account"
    refute html =~ "Sign In with GitHub"
  end

  test "landing page exposes the GitHub provider entrypoint when provider login is enabled", %{conn: conn} do
    enable_provider_login!(:github, "github.com")

    {:ok, view, _html} = live(conn, ~p"/welcome")

    assert has_element?(
             view,
             ~s|a[href="/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome"]|,
             "Sign In with GitHub"
           )

    assert has_element?(view, "a", "Sign In")
    assert has_element?(view, "a", "Create Account")
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
