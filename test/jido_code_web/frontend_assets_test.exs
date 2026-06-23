defmodule JidoCodeWeb.FrontendAssetsTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  # covers: architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented
  use ExUnit.Case, async: false

  alias JidoCodeWeb.FrontendAssets

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

  test "status uses the test manifest by default in test mode" do
    Application.delete_env(:jido_code, :frontend_assets_override)

    status = FrontendAssets.status()

    assert status.mode == :ready
    assert is_map(status.manifest)
  end

  test "status supports a fallback override with product-oriented detail" do
    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })

    status = FrontendAssets.status()
    delivery = FrontendAssets.vue_surface_delivery("ResetSurface")

    assert status.mode == :fallback
    assert delivery.mode == :fallback
    assert delivery.reason == :asset_manifest_unavailable
    assert delivery.title == "Interactive summary temporarily unavailable"
    assert delivery.detail =~ "server-rendered fallback mode"
    assert Map.has_key?(status.manifest, "js/app.js")
    assert Map.has_key?(status.manifest, "css/app.css")
  end

  test "status supports client-only overrides for SSR recovery paths" do
    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :client_only,
      reason: :ssr_unavailable
    })

    status = FrontendAssets.status()
    delivery = FrontendAssets.vue_surface_delivery("ResetSurface")

    assert status.mode == :client_only
    assert delivery.mode == :client_only
    assert delivery.ssr == false
    assert delivery.reason == :ssr_unavailable
  end
end
