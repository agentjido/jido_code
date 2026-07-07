defmodule JidoCodeWeb.UIResetPhase101ContributorGuidanceTest do
  use ExUnit.Case, async: true

  test "Mix aliases expose focused UI reset verification through frontend.verify" do
    mix = File.read!("mix.exs")

    assert mix =~ ~s("ui_reset.verify": :test)

    assert mix =~
             ~s("frontend.verify": ["assets.setup", "cmd npm run frontend:test", "assets.build", "ui_reset.verify"])

    assert mix =~ "ui_reset_phase_98_css_token_test.exs"
    assert mix =~ "ui_reset_phase_100_integration_test.exs"
    assert mix =~ "ui_reset_phase_101_resilience_test.exs"
    assert mix =~ "operator_area_shell_live_test.exs"
  end

  test "CI runs the frontend gate that includes UI reset guardrails" do
    ci = File.read!(".github/workflows/ci.yml")

    assert ci =~ "Verify frontend pipeline and UI reset guardrails"
    assert ci =~ "mix frontend.verify"
  end

  test "entrypoint docs describe the current frontend architecture and local gate" do
    for path <- ["README.md", "CONTRIBUTING.md", "AGENTS.md"] do
      source = File.read!(path)

      assert source =~ "JidoCodeWeb.Areas"
      assert source =~ "JidoCodeWeb.Components.UI"
      assert source =~ "shadcn-vue"
      assert source =~ "assets/vue/index.ts"
      assert source =~ "mix ui_reset.verify"
      assert source =~ "DaisyUI"
    end
  end

  test "developer guides explain how to extend areas, SaladUI wrappers, and Vue islands" do
    frontend = File.read!("docs/developer/09-frontend-and-product-surfaces.md")
    workflow = File.read!("docs/developer/10-development-workflow-and-quality-gates.md")

    assert frontend =~ "Adding A New Area"
    assert frontend =~ "Adding A SaladUI Wrapper"
    assert frontend =~ "Adding A shadcn-vue Island"
    assert frontend =~ "JidoCodeWeb.Areas"
    assert frontend =~ "JidoCodeWeb.Components.UI"
    assert frontend =~ "assets/vue/components/ui"
    assert frontend =~ "assets/vue/index.ts"
    assert frontend =~ "<.vue_surface"
    assert frontend =~ "import.meta.glob"

    assert workflow =~ "mix ui_reset.verify"
    assert workflow =~ "no-DaisyUI"
    assert workflow =~ "broad Vue"
    assert workflow =~ "old subject-tree shell"
  end
end
