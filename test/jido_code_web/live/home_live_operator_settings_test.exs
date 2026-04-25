defmodule JidoCodeWeb.HomeLiveOperatorSettingsTest do
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "signed-in welcome routes auth and integration management to settings", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123", return_owner: true)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(view, "#welcome-operator-settings-handoff", "Auth & Integrations Live In Settings")
    assert has_element?(view, ~s|a[href="/settings/auth"]#welcome-open-auth-settings|, "Open Auth & Integrations")
    assert has_element?(view, "#welcome-operator-settings-handoff", "Provider Login")
    assert has_element?(view, "#welcome-operator-settings-handoff", "Git Provider Integrations")

    refute has_element?(view, "#provider-login-settings")
    refute has_element?(view, "#git-provider-integrations")
    refute has_element?(view, "#refresh-github-service-checks")
  end
end
