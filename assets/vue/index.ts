import { h, type Component } from "vue"
import {
  createLiveVue,
  findComponent,
  type ComponentMap,
  type LiveHook,
} from "live_vue"
import DashboardRunSummaryWidget from "../../lib/jido_code_web/live/DashboardRunSummaryWidget.vue"
import DashboardRuntimePostureWidget from "../../lib/jido_code_web/live/DashboardRuntimePostureWidget.vue"
import ProjectDetailOverviewWidget from "../../lib/jido_code_web/live/ProjectDetailOverviewWidget.vue"
import ProjectDetailSemanticExplorerWidget from "../../lib/jido_code_web/live/ProjectDetailSemanticExplorerWidget.vue"
import RunGovernanceOverviewWidget from "../../lib/jido_code_web/live/RunGovernanceOverviewWidget.vue"
import SettingsOverviewWidget from "../../lib/jido_code_web/live/SettingsOverviewWidget.vue"
import SetupGitHubRepositorySelectorWidget from "../../lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue"
import SetupRuntimeDefaultsWidget from "../../lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue"
import SetupStartPathSelectorWidget from "../../lib/jido_code_web/live/SetupStartPathSelectorWidget.vue"
import WorkbenchSummaryWidget from "../../lib/jido_code_web/live/WorkbenchSummaryWidget.vue"

declare module "vue" {
  interface ComponentCustomProperties {
    $live: LiveHook
  }
}

export const liveVueComponents = {
  "../../lib/jido_code_web/live/DashboardRunSummaryWidget.vue": DashboardRunSummaryWidget,
  "../../lib/jido_code_web/live/DashboardRuntimePostureWidget.vue": DashboardRuntimePostureWidget,
  "../../lib/jido_code_web/live/ProjectDetailOverviewWidget.vue": ProjectDetailOverviewWidget,
  "../../lib/jido_code_web/live/ProjectDetailSemanticExplorerWidget.vue": ProjectDetailSemanticExplorerWidget,
  "../../lib/jido_code_web/live/RunGovernanceOverviewWidget.vue": RunGovernanceOverviewWidget,
  "../../lib/jido_code_web/live/SettingsOverviewWidget.vue": SettingsOverviewWidget,
  "../../lib/jido_code_web/live/SetupGitHubRepositorySelectorWidget.vue": SetupGitHubRepositorySelectorWidget,
  "../../lib/jido_code_web/live/SetupRuntimeDefaultsWidget.vue": SetupRuntimeDefaultsWidget,
  "../../lib/jido_code_web/live/SetupStartPathSelectorWidget.vue": SetupStartPathSelectorWidget,
  "../../lib/jido_code_web/live/WorkbenchSummaryWidget.vue": WorkbenchSummaryWidget,
} satisfies ComponentMap

export function resolveLiveVueComponent(name: string) {
  return findComponent(liveVueComponents, name)
}

export default createLiveVue({
  resolve: resolveLiveVueComponent,
  setup: ({ createApp, component, props, slots, plugin, el }) => {
    const app = createApp({ render: () => h(component as Component, props, slots) })

    app.use(plugin)
    app.mount(el)

    return app
  },
})
