defmodule JidoCodeWeb.PhaseTwelveIntegrationTest do
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  use JidoCodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "shared host shell can mount a live vue component", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, JidoCodeWeb.TestSupport.LiveVueHostShellLive)

    vue = LiveVue.Test.get_vue(view, id: "shell-probe")

    assert vue.component == "ShellProbe"
    assert vue.props["label"] == "LiveVue ready"
    assert vue.ssr == false
    assert vue.use_diff == false
  end

  test "plain liveview routes render without a vue mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/welcome")

    refute html =~ ~s(phx-hook="VueHook")
  end

  test "root layout renders test-safe vite asset references", %{conn: conn} do
    conn = get(conn, ~p"/welcome")
    html = html_response(conn, 200)

    assert html =~ "assets/test.css?vsn=d"
    assert html =~ "assets/test.js?vsn=d"
  end
end
