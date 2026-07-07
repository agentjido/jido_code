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

    assert inventory =~ "`package.json` includes `daisyui`"
    assert inventory =~ "`assets/css/app.css` imports DaisyUI plugin and themes"
    assert inventory =~ "`btn`, `badge`, `alert`, `tabs`, `base-*`, `rounded-box`, `join-*`"
    assert inventory =~ "replace with generated shadcn-vue primitives"
  end
end
