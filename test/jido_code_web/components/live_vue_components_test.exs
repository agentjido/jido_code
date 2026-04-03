defmodule JidoCodeWeb.LiveVueComponentsTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  use ExUnit.Case, async: true

  import JidoCodeWeb.LiveVueCase
  import Phoenix.LiveViewTest

  test "vue_surface normalizes event bindings into JS handlers" do
    html =
      render_component(&JidoCodeWeb.LiveVueComponents.vue_surface/1, %{
        component: "BoundaryProbe",
        events: %{"request-sync" => "request_sync"},
        id: "boundary-probe",
        props: %{status: "idle"},
        socket: nil
      })

    assert_vue_component(html, "BoundaryProbe", id: "boundary-probe")
    assert_vue_prop(html, :status, "idle", id: "boundary-probe")
    assert_vue_handler(html, "request-sync", "request_sync", id: "boundary-probe")
  end

  test "vue_surface rejects reserved prop keys" do
    assert_raise ArgumentError, ~r/reserved prop key/, fn ->
      render_component(&JidoCodeWeb.LiveVueComponents.vue_surface/1, %{
        component: "BoundaryProbe",
        props: %{"v-socket" => "bad"},
        socket: nil
      })
    end
  end
end
