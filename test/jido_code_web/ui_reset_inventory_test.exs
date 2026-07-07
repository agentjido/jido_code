defmodule JidoCodeWeb.UIResetInventoryTest do
  use ExUnit.Case, async: true

  @inventory_path ".planning/ui-reset-inventory.md"

  test "inventory names every current LiveView surface" do
    inventory = File.read!(@inventory_path)

    for path <- Path.wildcard("lib/jido_code_web/live/*_live.ex") do
      assert inventory =~ path
    end
  end

  test "inventory names every current HEEx component surface" do
    inventory = File.read!(@inventory_path)

    for path <- Path.wildcard("lib/jido_code_web/components/*.ex") do
      assert inventory =~ path
    end
  end

  test "inventory names every current LiveVue widget" do
    inventory = File.read!(@inventory_path)

    for path <- Path.wildcard("lib/jido_code_web/live/*.vue") do
      assert inventory =~ path
    end
  end

  test "inventory records current DaisyUI removal boundaries" do
    inventory = File.read!(@inventory_path)

    assert inventory =~ "`package.json` and `package-lock.json` omit `daisyui`"
    assert inventory =~ "`assets/css/app.css` omits DaisyUI plugin and theme blocks"
    assert inventory =~ "guard against new `btn`, `badge`, `alert`, `tabs`, `base-*`, `rounded-box`, and `join-*`"
    assert inventory =~ "Retained widgets import generated shadcn-vue primitives from `@/vue/components/ui/*`"
    assert inventory =~ "`lib/jido_code_web/components/route_shell_components.ex` | route frame"
    assert inventory =~ "`lib/jido_code_web/components/operator_shell_components.ex` | deleted legacy shell"
  end
end
