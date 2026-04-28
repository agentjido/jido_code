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

async function expectDashboardUrl(
  page: Page,
  options: { subject: string; section: string; onboarding?: string }
) {
  await page.waitForURL(url => {
    if (url.pathname !== "/dashboard") {
      return false
    }

    return (
      url.searchParams.get("subject") === options.subject &&
      url.searchParams.get("section") === options.section &&
      (options.onboarding === undefined ||
        url.searchParams.get("onboarding") === options.onboarding)
    )
  })
}

async function shellLayoutMetrics(page: Page, sidebarSelector: string, paneSelector: string) {
  return page.evaluate(
    ([sidebarQuery, paneQuery]) => {
      const sidebar = document.querySelector(sidebarQuery)
      const pane = document.querySelector(paneQuery)

      if (!(sidebar instanceof HTMLElement) || !(pane instanceof HTMLElement)) {
        return null
      }

      const sidebarBox = sidebar.getBoundingClientRect()
      const paneBox = pane.getBoundingClientRect()

      return {
        sidebarLeft: sidebarBox.left,
        sidebarRight: sidebarBox.right,
        sidebarBottom: sidebarBox.bottom,
        paneLeft: paneBox.left,
        paneTop: paneBox.top,
      }
    },
    [sidebarSelector, paneSelector] as const
  )
}

async function expectSidebarLeftOfPane(page: Page, sidebarSelector: string, paneSelector: string) {
  const metrics = await shellLayoutMetrics(page, sidebarSelector, paneSelector)

  expect(metrics).not.toBeNull()
  expect((metrics?.sidebarRight ?? 0) + 12).toBeLessThan(metrics?.paneLeft ?? 0)
}

async function expectSidebarAbovePane(page: Page, sidebarSelector: string, paneSelector: string) {
  const metrics = await shellLayoutMetrics(page, sidebarSelector, paneSelector)

  expect(metrics).not.toBeNull()
  expect((metrics?.sidebarBottom ?? 0) - 4).toBeLessThanOrEqual(metrics?.paneTop ?? 0)
  expect(Math.abs((metrics?.sidebarLeft ?? 0) - (metrics?.paneLeft ?? 0))).toBeLessThan(12)
}

test("dashboard subject-tree shell keeps the ready-state landing route scanable on wide screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 1440, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expectDashboardUrl(page, { subject: "work", section: "overview", onboarding: "completed" })
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-subject", "work")
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-section", "overview")
  await expect(page.locator("#dashboard-shell-breadcrumbs")).toBeVisible()
  await expect(page.locator("#dashboard-shell-parent-subjects")).toBeVisible()
  await expect(page.locator("#dashboard-sidebar-shell")).toBeVisible()
  await expect(page.locator("#dashboard-section-nav")).toBeVisible()
  await expect(page.locator("#dashboard-shell-parent-subjects-work")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#dashboard-section-nav-overview")).toHaveAttribute("aria-controls", "dashboard-pane-overview")
  await expect(page.locator("#dashboard-settings-handoff")).toContainText("Settings")
  await expectSidebarLeftOfPane(page, "#dashboard-sidebar-shell", "#dashboard-pane-overview")
  await expect(page.locator("#dashboard-pane-overview-header")).toContainText("Dashboard overview")
  await expect(page.locator("#dashboard-pane-overview-middle")).toBeVisible()
  await expect(page.locator("#dashboard-pane-overview-footer")).toBeVisible()
  await expect(page.locator("#dashboard-overview-panel")).toHaveCount(1)
  await expect(page.locator("#dashboard-overview-note")).toBeVisible()
  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()
  await expect(page.locator("[id^='dashboard-overview-repository-card-']").first()).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-runs")
  await expectDashboardUrl(page, { subject: "work", section: "runs", onboarding: "completed" })
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-subject", "work")
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-section", "runs")
  await expect(page.locator("#dashboard-section-nav-runs")).toHaveAttribute("aria-controls", "dashboard-pane-runs")
  await expect(page.locator("#dashboard-pane-runs-header")).toContainText("Recent governed runs")
  await expect(page.locator("#dashboard-run-summaries")).toBeVisible()
  await expect(page.locator("#dashboard-overview-panel")).toHaveCount(0)

  await activateTab(page, "#dashboard-section-nav-conversations")
  await expectDashboardUrl(page, { subject: "work", section: "conversations", onboarding: "completed" })
  await expect(page.locator("#dashboard-conversation-supervision")).toBeVisible()
  await expect(page.locator("#dashboard-run-summaries")).toHaveCount(0)

  await activateTab(page, "#dashboard-shell-parent-subjects-knowledge")
  await expectDashboardUrl(page, { subject: "knowledge", section: "memory", onboarding: "completed" })
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-subject", "knowledge")
  await expect(page.locator("#dashboard-shell-parent-subjects-knowledge")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#dashboard-memory-summaries")).toBeVisible()
  await expect(page.locator("#dashboard-section-nav-memory")).toHaveAttribute("aria-current", "page")

  await activateTab(page, "#dashboard-shell-parent-subjects-runtime")
  await expectDashboardUrl(page, { subject: "runtime", section: "runtime", onboarding: "completed" })
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-subject", "runtime")
  await expect(page.locator("#dashboard-shell-parent-subjects-runtime")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#dashboard-runtime-evidence")).toBeVisible()

  await activateTab(page, "#dashboard-shell-parent-subjects-work")
  await expectDashboardUrl(page, { subject: "work", section: "overview", onboarding: "completed" })

  await activateTab(page, "#dashboard-section-nav-next_steps")
  await expectDashboardUrl(page, { subject: "work", section: "next_steps", onboarding: "completed" })
  await expect(page.locator("#dashboard-onboarding-next-actions")).toBeVisible()
})

test("dashboard subject navigation stays usable as a wrapped fallback on narrow screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 430, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.locator("#dashboard-shell-breadcrumbs")).toBeVisible()
  await expect(page.locator("#dashboard-shell-parent-subjects")).toBeVisible()
  await expect(page.locator("#dashboard-sidebar-shell")).toBeVisible()
  await expect(page.locator("#dashboard-section-nav")).toBeVisible()
  await expectNoHorizontalOverflow(page, "#dashboard-shell-parent-subjects")
  await expectNoHorizontalOverflow(page, "#dashboard-section-nav")
  await expectSidebarAbovePane(page, "#dashboard-sidebar-shell", "#dashboard-pane-overview")
  await expect(page.locator("#dashboard-overview-panel")).toHaveCount(1)
  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-next_steps")
  await expectDashboardUrl(page, { subject: "work", section: "next_steps", onboarding: "completed" })
  await expect(page.locator("#dashboard-onboarding-next-actions")).toBeVisible()

  await activateTab(page, "#dashboard-shell-parent-subjects-knowledge")
  await expectDashboardUrl(page, { subject: "knowledge", section: "memory", onboarding: "completed" })
  await expect(page.locator("#dashboard-memory-summaries")).toBeVisible()

  await activateTab(page, "#dashboard-shell-parent-subjects-work")
  await expectDashboardUrl(page, { subject: "work", section: "overview", onboarding: "completed" })

  await activateTab(page, "#dashboard-section-nav-conversations")
  await expectDashboardUrl(page, { subject: "work", section: "conversations", onboarding: "completed" })
  await expect(page.locator("#dashboard-conversation-supervision")).toBeVisible()

  await activateTab(page, "#dashboard-section-nav-overview")
  await expectDashboardUrl(page, { subject: "work", section: "overview", onboarding: "completed" })
  await expect(page.locator("#dashboard-overview-panel")).toHaveCount(1)
  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()
})

test("dashboard overview shows repository monitoring cards on wide screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 1440, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expectDashboardUrl(page, { subject: "work", section: "overview", onboarding: "completed" })
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-subject", "work")
  await expect(page.locator("#dashboard-root")).toHaveAttribute("data-dashboard-section", "overview")
  await expect(page.locator("#dashboard-overview-panel")).toHaveCount(1)
  await expect(page.locator("#dashboard-overview-note")).toBeVisible()
  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()
  await expect(page.locator("[id^='dashboard-overview-repository-card-']").first()).toBeVisible()
  await expect(page.locator("[id^='dashboard-overview-repository-accordion-toggle-']").first()).toBeVisible()
})

test("dashboard overview stays bounded on narrow screens", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 430, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.locator("#dashboard-overview-panel")).toHaveCount(1)
  await expectNoHorizontalOverflow(page, "#dashboard-content-shell")
  await expect(page.locator("#dashboard-overview-repository-list")).toBeVisible()
  await expect(page.locator("[id^='dashboard-overview-repository-card-']").first()).toBeVisible()
  await expect(page.locator("[id^='dashboard-overview-repository-accordion-toggle-']").first()).toBeVisible()
})
