import { renderToString } from "@vue/server-renderer"
import { createSSRApp, h } from "vue"
import { describe, expect, it } from "vitest"
import { Alert, AlertDescription, AlertTitle } from "@/vue/components/ui/alert"
import { Badge } from "@/vue/components/ui/badge"
import { Button } from "@/vue/components/ui/button"

describe("shadcn-vue primitive SSR preview", () => {
  it("renders generated primitives without registering them as LiveVue routes", async () => {
    const app = createSSRApp({
      render: () =>
        h("section", { id: "shadcn-primitive-preview" }, [
          h(Button, { variant: "outline" }, () => "Review"),
          h(Badge, { variant: "secondary" }, () => "Primitive"),
          h(Alert, { variant: "default" }, () => [
            h(AlertTitle, () => "Primitive ready"),
            h(AlertDescription, () => "Rendered through Vue SSR"),
          ]),
        ]),
    })

    const html = await renderToString(app)

    expect(html).toContain("shadcn-primitive-preview")
    expect(html).toContain("Review")
    expect(html).toContain("Primitive")
    expect(html).toContain("Rendered through Vue SSR")
  })
})
