defmodule JidoCodeWeb.HomeLiveOperatorSettingsTest do
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "signed-in welcome keeps auth and integration management out of the landing surface", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123", return_owner: true)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/welcome")

    assert has_element?(view, ~s|a[href="/settings/auth"]#welcome-open-settings|, "Open Auth & Integrations")
    refute has_element?(view, "#provider-login-settings")
    refute has_element?(view, "#git-provider-integrations")
    refute has_element?(view, "#refresh-github-service-checks")
    refute has_element?(view, "#welcome-operator-settings-handoff")
  end
end
