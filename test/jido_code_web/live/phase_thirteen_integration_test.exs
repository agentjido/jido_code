defmodule JidoCodeWeb.PhaseThirteenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  use JidoCodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.JS

  test "hybrid surface mounts through the shared boundary with bounded props and handlers", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, JidoCodeWeb.TestSupport.LiveVueBoundaryLive)

    assert has_element?(view, "#boundary-probe")

    vue = assert_vue_component(view, "BoundaryProbe", id: "boundary-probe")

    assert vue.props["status"] == "idle"
    assert is_map(vue.props["taskForm"])
    assert is_map(vue.props["uploadConfig"])
    assert_vue_handler(view, "request-sync", JS.push("request_sync", value: %{origin: "vue"}), id: "boundary-probe")
    assert_vue_handler(view, "simulate-failure", "simulate_failure", id: "boundary-probe")
  end

  test "server refresh updates props and stream diffs without giving up liveview ownership", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, JidoCodeWeb.TestSupport.LiveVueBoundaryLive)

    render_click(element(view, "#server-sync"))

    vue = vue(view, id: "boundary-probe")

    assert vue.props["status"] == "synced"

    assert Enum.any?(vue.streams_diff, fn
             ["upsert", "/items/-", %{"label" => "Server refresh"}] -> true
             _ -> false
           end)
  end

  test "typed server failures surface as bounded vue props", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, JidoCodeWeb.TestSupport.LiveVueBoundaryLive)

    render_click(element(view, "#server-failure"))

    vue = vue(view, id: "boundary-probe")

    assert vue.props["failure"] == %{"kind" => "validation", "message" => "Need a title"}
  end

  test "plain liveview routes keep using the normal test path", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/welcome")

    assert has_element?(view, "#system-check")
    refute render(view) =~ ~s(phx-hook="VueHook")
  end
end
