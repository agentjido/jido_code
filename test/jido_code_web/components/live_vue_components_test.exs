defmodule JidoCodeWeb.LiveVueComponentsTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  use ExUnit.Case, async: true

  import JidoCodeWeb.LiveVueCase
  import Phoenix.LiveViewTest

  setup do
    original_override = Application.get_env(:jido_code, :frontend_assets_override, :__missing__)

    on_exit(fn ->
      case original_override do
        :__missing__ -> Application.delete_env(:jido_code, :frontend_assets_override)
        value -> Application.put_env(:jido_code, :frontend_assets_override, value)
      end
    end)

    :ok
  end

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

  test "vue_surface falls back to a product-oriented compatibility notice when frontend delivery is unavailable" do
    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })

    html =
      render_component(&JidoCodeWeb.LiveVueComponents.vue_surface/1, %{
        component: "BoundaryProbe",
        id: "boundary-probe",
        socket: nil
      })

    assert html =~ "Interactive summary temporarily unavailable"
    assert html =~ "server-rendered fallback mode"
    assert html =~ "Fallback mode reason: Asset manifest unavailable"
    refute html =~ ~s(phx-hook="VueHook")
  end

  test "vue_surface keeps rendering in client-only mode when SSR is degraded" do
    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :client_only,
      reason: :ssr_unavailable
    })

    html =
      render_component(&JidoCodeWeb.LiveVueComponents.vue_surface/1, %{
        component: "BoundaryProbe",
        id: "boundary-probe",
        props: %{status: "idle"},
        socket: nil
      })

    vue = assert_vue_component(html, "BoundaryProbe", id: "boundary-probe")

    assert vue.props["status"] == "idle"
    assert vue.ssr == false
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
