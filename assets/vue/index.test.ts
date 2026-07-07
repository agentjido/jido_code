import { describe, expect, it } from "vitest"
import { liveVueComponents, resolveLiveVueComponent } from "./index"

describe("LiveVue island registry", () => {
  it("registers only production-mounted islands", () => {
    expect(Object.keys(liveVueComponents).sort()).toEqual([
      "../../lib/jido_code_web/live/DashboardRunSummaryWidget.vue",
      "../../lib/jido_code_web/live/DashboardRuntimePostureWidget.vue",
      "../../lib/jido_code_web/live/ProjectDetailOverviewWidget.vue",
      "../../lib/jido_code_web/live/ProjectDetailSemanticExplorerWidget.vue",
      "../../lib/jido_code_web/live/RunGovernanceOverviewWidget.vue",
      "../../lib/jido_code_web/live/SettingsOverviewWidget.vue",
      "../../lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue",
      "../../lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue",
      "../../lib/jido_code_web/live/SetupStartPathSelectorWidget.vue",
      "../../lib/jido_code_web/live/WorkbenchSummaryWidget.vue",
    ])
  })

  it("resolves mounted island names through the explicit registry", () => {
    expect(resolveLiveVueComponent("DashboardRunSummaryWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("DashboardRuntimePostureWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("ProjectDetailOverviewWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("ProjectDetailSemanticExplorerWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("RunGovernanceOverviewWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("SettingsOverviewWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("SetupGitHubRepositorySelectorWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("SetupRuntimeDefaultsWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("SetupStartPathSelectorWidget")).toBeTruthy()
    expect(resolveLiveVueComponent("WorkbenchSummaryWidget")).toBeTruthy()
  })

  it("does not expose generated shadcn-vue primitives as mount targets", () => {
    expect(() => resolveLiveVueComponent("components/ui/button/Button")).toThrow(/not found/i)
    expect(() => resolveLiveVueComponent("components/ui/dialog/Dialog")).toThrow(/not found/i)
    expect(() => resolveLiveVueComponent("components/ui/table/Table")).toThrow(/not found/i)
    expect(() => resolveLiveVueComponent("components/ui/tabs/Tabs")).toThrow(/not found/i)
  })
})
