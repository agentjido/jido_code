import {h, type Component} from "vue"
import {
  createLiveVue,
  findComponent,
  type ComponentMap,
  type LiveHook,
} from "live_vue"

declare module "vue" {
  interface ComponentCustomProperties {
    $live: LiveHook
  }
}

export const liveVueComponents = {} satisfies ComponentMap

export function resolveLiveVueComponent(name: string) {
  return findComponent(liveVueComponents, name)
}

export default createLiveVue({
  resolve: resolveLiveVueComponent,
  setup: ({createApp, component, props, slots, plugin, el}) => {
    const app = createApp({render: () => h(component as Component, props, slots)})

    app.use(plugin)
    app.mount(el)

    return app
  },
})
