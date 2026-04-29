// covers: architecture.operator_surface_information_architecture.signed_in_routes_share_global_wayfinding
// covers: architecture.operator_surface_information_architecture.global_wayfinding_uses_shared_liveview_helpers
import { expect, test, type APIRequestContext, type Page } from "@playwright/test"

async function waitForLiveViewConnection(page: Page) {
  await page.waitForFunction(() => {
    const liveSocket = (window as Window & { liveSocket?: { isConnected?: () => boolean } }).liveSocket
    return typeof liveSocket?.isConnected === "function" && liveSocket.isConnected()
  })
}

async function prepareScenario(request: APIRequestContext, mode: "conversation_ready") {
  let lastResponse: Awaited<ReturnType<APIRequestContext["get"]>> | null = null

  for (let attempt = 0; attempt < 5; attempt += 1) {
    lastResponse = await request.get(`/_test/browser/scenario?mode=${mode}`)

    if (lastResponse.ok()) {
      return
    }

    await new Promise(resolve => setTimeout(resolve, 250))
  }

  throw new Error(
    `scenario ${mode} failed with status ${lastResponse?.status()} and body ${await lastResponse?.text()}`
  )
}

async function signIn(page: Page, destination: string) {
  const expected = new URL(`http://localhost${destination}`)

  await page.goto(`/_test/browser/sign-in?to=${encodeURIComponent(destination)}`)
  await page.waitForURL(url => url.pathname === expected.pathname || url.pathname === "/setup")

  if (page.url().includes("/setup")) {
    await page.goto(destination)
    await page.waitForURL(url => url.pathname === expected.pathname)
  }

  await waitForLiveViewConnection(page)
}

async function expectNoHorizontalOverflow(page: Page, selector: string) {
  const metrics = await page.evaluate(query => {
    const element = document.querySelector(query)

    if (!(element instanceof HTMLElement)) {
      return null
    }

    return {
      clientWidth: element.clientWidth,
      scrollWidth: element.scrollWidth,
    }
  }, selector)

  expect(metrics).not.toBeNull()
  expect((metrics?.scrollWidth ?? 0) - (metrics?.clientWidth ?? 0)).toBeLessThanOrEqual(2)
}

async function openRepoDetailFromWorkbench(page: Page, githubFullName: string) {
  const repoRow = page.locator("tr", { hasText: githubFullName })
  await expect(repoRow).toBeVisible()
  await repoRow.getByRole("link", { name: /^Repo detail$/ }).first().click()
  await page.waitForURL(url => url.pathname.startsWith("/repos/"))
  await waitForLiveViewConnection(page)
}

test("global operator nav moves across major signed-in routes without browser back", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.locator("#operator-global-nav")).toBeVisible()
  await expect(page.locator("#operator-global-nav-dashboard")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#operator-route-badge")).toContainText("Authenticated home")

  await page.locator("#operator-global-nav-settings").click()
  await page.waitForURL(url => url.pathname === "/settings")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#operator-global-nav-settings")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#operator-context-settings-tab")).toContainText("GitHub settings")

  await page.locator("#operator-global-nav-workbench").click()
  await page.waitForURL(url => url.pathname === "/workbench")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#operator-global-nav-workbench")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#workbench-route-role-label")).toContainText("Dense specialist mode")

  await page.locator("#operator-global-nav-repositories").click()
  await page.waitForURL(url => url.pathname === "/repos")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#operator-global-nav-repositories")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#project-inventory-table")).toBeVisible()
})

test("global operator nav preserves the broader selected parent surface on repo detail routes", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/dashboard?onboarding=completed")

  await page.locator("[id^='dashboard-overview-repository-issues-project-link-']").first().click()
  await page.waitForURL(url => url.pathname.startsWith("/repos/"))
  await waitForLiveViewConnection(page)
  await expect(page.locator("#operator-global-nav-dashboard")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#operator-context-repo")).toBeVisible()

  await page.goto("/workbench")
  await waitForLiveViewConnection(page)
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-ready")
  await expect(page.locator("#operator-global-nav-workbench")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#project-detail-breadcrumb-return")).toHaveAttribute("href", "/workbench")
})

test("repositories-origin and narrow-screen operator nav stay legible on direct repo follow-up", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 430, height: 1000 })
  await signIn(page, "/repos")

  await expect(page.locator("#operator-global-nav")).toBeVisible()
  await expectNoHorizontalOverflow(page, "#operator-global-nav")
  await expect(page.locator("#operator-global-nav-repositories")).toHaveAttribute("aria-current", "page")

  await page.locator("[id^='project-inventory-open-']").first().click()
  await page.waitForURL(url => url.pathname.startsWith("/repos/"))
  await waitForLiveViewConnection(page)
  await expect(page.locator("#operator-global-nav-repositories")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#project-detail-breadcrumb-return")).toHaveAttribute("href", "/repos")
  await expect(page.locator("#project-detail-breadcrumb-return")).toContainText("Repositories")
})

test("adjacent signed-in routes keep proportional shells and route-owned navigation on narrow screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 430, height: 1000 })
  await signIn(page, "/workbench")

  await expect(page.locator("#operator-global-nav")).toBeVisible()
  await expectNoHorizontalOverflow(page, "#operator-global-nav")

  await expect(page.locator("#workbench-shell")).toBeVisible()
  await expect(page.locator("#workbench-shell-parent-subjects")).toHaveCount(0)
  await expect(page.locator("#workbench-pane-footer")).toBeVisible()
  await expect(page.locator("#workbench-return-dashboard")).toBeVisible()
  await expect(page.locator("#workbench-apply-filters")).toBeVisible()

  await page.locator("#operator-global-nav-repositories").click()
  await page.waitForURL(url => url.pathname === "/repos")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#project-inventory-shell")).toBeVisible()
  await expect(page.locator("#project-inventory-shell-parent-subjects")).toHaveCount(0)
  await expect(page.locator("#project-inventory-pane-footer")).toBeVisible()
  await expect(page.locator("#project-inventory-reset-filters")).toBeVisible()
  await expect(page.locator("#project-inventory-apply-filters")).toBeVisible()

  await page.locator("#operator-global-nav-workflows").click()
  await page.waitForURL(url => url.pathname === "/workflows")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#workflows-shell")).toBeVisible()
  await expect(page.locator("#workflows-shell-parent-subjects")).toHaveCount(0)
  await expect(page.locator("#workflows-start-run")).toBeVisible()

  await page.locator("#operator-global-nav-agents").click()
  await page.waitForURL(url => url.pathname === "/agents")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#agents-shell")).toBeVisible()
  await expect(page.locator("#agents-shell-parent-subjects")).toHaveCount(0)
  await expect(page.locator("#agents-project-table")).toBeVisible()

  await page.locator("#operator-global-nav-settings").click()
  await page.waitForURL(url => url.pathname === "/settings")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#settings-shell")).toBeVisible()
  await expect(page.locator("#settings-shell-parent-subjects")).toHaveCount(0)
  await expect(page.locator("#settings-nav-github")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#settings-github-open-add-modal")).toBeVisible()

  await page.locator("#settings-nav-security").click()
  await page.waitForURL(url => url.pathname === "/settings/security")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#settings-nav-security")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#settings-pane-security")).toBeVisible()
  await expect(page.locator("#settings-pane-security-footer")).toHaveCount(0)
  await expect(page.locator("#operator-context-settings-tab")).toContainText("Security settings")
})
