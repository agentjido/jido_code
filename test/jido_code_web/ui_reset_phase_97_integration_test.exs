defmodule JidoCodeWeb.UIResetPhase97IntegrationTest do
  use ExUnit.Case, async: true

  @phase_path ".planning/phase-97-ui-reset-contract-and-external-shell-inventory.md"
  @index_path ".planning/README.md"
  @inventory_path ".planning/ui-reset-inventory.md"
  @policy_path ".planning/ui-reset-policy.md"
  @frontend_doc_path "docs/developer/09-frontend-and-product-surfaces.md"

  test "phase 97 planning track is indexed and complete" do
    phase = File.read!(@phase_path)
    index = File.read!(@index_path)

    assert index =~ "Phase 97 - UI Reset Contract And External Shell Inventory"
    assert index =~ "Phase 98 - SaladUI And Shadcn-Vue Foundation"
    assert index =~ "Phase 99 - Root Area Shell Routing And Button Menu"
    assert index =~ "Phase 100 - Product Surface Rebuild And Legacy UI Deletion"
    assert index =~ "Phase 101 - UI Reset Hardening And Contributor Convergence"

    assert phase =~ "[x] 97 Phase 97 - UI Reset Contract And External Shell Inventory"
    assert phase =~ "[x] 97.1 Section - Target Shell Contract"
    assert phase =~ "[x] 97.2 Section - Current UI Deletion Inventory"
    assert phase =~ "[x] 97.3 Section - Deletion Policy And Migration Order"
    assert phase =~ "[x] 97.4 Section - Integration Tests"
  end

  test "inventory distinguishes root areas, detail routes, and public setup routes" do
    inventory = File.read!(@inventory_path)

    assert inventory =~ "`lib/jido_code_web/live/dashboard_live.ex` | root area"
    assert inventory =~ "`lib/jido_code_web/live/project_inventory_live.ex` | root area"
    assert inventory =~ "`lib/jido_code_web/live/run_detail_live.ex` | detail route"
    assert inventory =~ "`lib/jido_code_web/live/work_item_detail_live.ex` | detail route"
    assert inventory =~ "`lib/jido_code_web/live/home_live.ex` | public/bootstrap route"
    assert inventory =~ "`lib/jido_code_web/live/setup_live.ex` | public/setup route"
  end

  test "phase artifacts define the no-compatibility UI reset boundary" do
    inventory = File.read!(@inventory_path)
    policy = File.read!(@policy_path)

    assert inventory =~ "Historical browser chrome, subject-tree navigation, DaisyUI component"
    assert inventory =~ "broad Vue auto-registration are implementation that has been"
    assert policy =~ "No DaisyUI compatibility layer remains after the cutover phase."
    assert policy =~ "Old route chrome, subject-tree helpers, operator-navigation helpers"
    assert policy =~ "Generated shadcn-vue primitives live under `assets/vue/components/ui`"
  end

  test "developer guidance names the new target shell and component split" do
    doc = File.read!(@frontend_doc_path)

    assert doc =~ "ariston-style area shell"
    assert doc =~ "top button menu"
    assert doc =~ "SaladUI"
    assert doc =~ "generated shadcn-vue"
    assert doc =~ "DaisyUI"
  end
end
