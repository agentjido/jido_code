// covers: package.jido_code.version_controlled_quality_surfaces
// covers: architecture.frontend_stack.liveview_remains_product_host_shell
// covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
// covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
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

async function signIn(page: Page, to: string) {
  await page.goto(`/_test/browser/sign-in?to=${encodeURIComponent(to)}`)

  await page.waitForURL(url => url.pathname === "/dashboard" || url.pathname === "/setup")

  if (page.url().includes("/setup")) {
    await page.goto(to)
    await page.waitForURL(url => url.pathname === "/dashboard")
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

async function activateTab(page: Page, selector: string) {
  const locator = page.locator(selector)
  await expect(locator).toBeVisible()

  const href = await locator.getAttribute("href")

  if (!href) {
    throw new Error(`missing href for ${selector}`)
  }

  await page.goto(href)
  await waitForLiveViewConnection(page)
}

async function expandFirstOverviewRepository(page: Page) {
  const toggle = page.locator("[id^='dashboard-overview-repository-accordion-toggle-']").first()
  await expect(toggle).toBeVisible()
  await toggle.click()

  const panel = page.locator("[id^='dashboard-overview-repository-accordion-panel-']").first()
  await expect(panel).toBeVisible()

  return panel
}

test("dashboard sidebar keeps the ready-state landing route scanable on wide screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 1440, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-section", "overview")
  await expect(page.locator("#dashboard-sidebar-shell")).toBeVisible()
  await expect(page.locator("#dashboard-section-nav")).toBeVisible()
  await expect(page.locator("#dashboard-settings-handoff")).toContainText("Settings")
  await expect(page.locator("#dashboard-overview-panel")).toBeVisible()
  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-runs")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=runs$/)
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-section", "runs")
  await expect(page.locator("#dashboard-run-summaries")).toBeVisible()
  await expect(page.locator("#dashboard-overview-panel")).toHaveCount(0)

  await activateTab(page, "#dashboard-section-nav-conversations")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=conversations$/)
  await expect(page.locator("#dashboard-conversation-supervision")).toBeVisible()
  await expect(page.locator("#dashboard-run-summaries")).toHaveCount(0)

  await activateTab(page, "#dashboard-section-nav-memory")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=memory$/)
  await expect(page.locator("#dashboard-memory-summaries")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-runtime")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=runtime$/)
  await expect(page.locator("#dashboard-runtime-evidence")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-next_steps")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=next_steps$/)
  await expect(page.locator("#dashboard-onboarding-next-actions")).toBeVisible()
})

test("dashboard sidebar navigation stays usable as a wrapped fallback on narrow screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 430, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.locator("#dashboard-sidebar-shell")).toBeVisible()
  await expect(page.locator("#dashboard-section-nav")).toBeVisible()
  await expectNoHorizontalOverflow(page, "#dashboard-section-nav")
  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-next_steps")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=next_steps$/)
  await expect(page.locator("#dashboard-onboarding-next-actions")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-conversations")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=conversations$/)
  await expect(page.locator("#dashboard-conversation-supervision")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-overview")
  await expect(page).toHaveURL(/\/dashboard\?onboarding=completed&section=overview$/)
  await expect(page.locator("#dashboard-overview-panel")).toBeVisible()
})

test("dashboard overview repository panels expand bounded monitoring detail on wide screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 1440, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-section", "overview")
  await expect(page.locator("[id^='dashboard-overview-repository-card-']").first()).toBeVisible()
  await expect(page.locator("[id^='dashboard-overview-repository-accordion-shell-']").first()).toBeVisible()

  const panel = await expandFirstOverviewRepository(page)

  await expect(panel).toContainText(/Open repository|No governed run, conversation, memory, or runtime detail has materialized/)
})

test("dashboard overview repository accordions stay usable on narrow screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 430, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()
  await expectNoHorizontalOverflow(page, "#dashboard-overview-repository-list")

  const panel = await expandFirstOverviewRepository(page)

  await expectNoHorizontalOverflow(page, "#dashboard-overview-repository-list")
  await expect(panel).toBeVisible()
})
