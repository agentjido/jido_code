// covers: architecture.frontend_stack.root_area_shell_owns_navigation
// covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces
// covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
import { mkdirSync } from "node:fs"
import path from "node:path"
import { expect, test, type APIRequestContext, type Page } from "@playwright/test"

const screenshotDir = path.resolve("tmp/ui-reset-final")

async function waitForLiveViewConnection(page: Page) {
  await page.waitForFunction(() => {
    const liveSocket = (window as Window & { liveSocket?: { isConnected?: () => boolean } }).liveSocket
    return typeof liveSocket?.isConnected === "function" && liveSocket.isConnected()
  })
}

async function prepareScenario(request: APIRequestContext, mode: string) {
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

  if (page.url().includes("/setup") && expected.pathname !== "/setup") {
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

async function capture(page: Page, name: string) {
  mkdirSync(screenshotDir, { recursive: true })
  await page.screenshot({ path: path.join(screenshotDir, `${name}.png`), fullPage: true })
}

test("public welcome stays outside the authenticated operator shell", async ({ page, request }) => {
  await prepareScenario(request, "normal")
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto("/welcome")

  await expect(page.getByRole("main")).toBeVisible()
  await expect(page.locator("#operator-app-shell")).toHaveCount(0)
  await expect(page.locator("#continue-setup-owner-form")).toBeVisible()
  await expect(page.getByRole("heading", { name: "Sign in to finish onboarding" })).toBeVisible()

  await capture(page, "welcome-public-desktop")
})

test("authenticated area shell exposes accessible navigation, status, tables, and dialogs", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "conversation_ready")
  await page.setViewportSize({ width: 1440, height: 1100 })
  await signIn(page, "/dashboard?onboarding=completed")

  await expect(page.getByRole("navigation", { name: "Product areas" })).toBeVisible()
  await expect(page.getByRole("status", { name: "Operator shell status" })).toBeVisible()
  await expect(page.locator("#operator-app-shell")).toHaveAttribute("data-active-area", "dashboard")
  await expect(page.locator("#operator-area-menu-dashboard")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#dashboard-shell-section-groups")).toHaveAttribute(
    "aria-label",
    "Route section groups"
  )
  await expect(page.locator("#dashboard-section-nav-overview")).toHaveAttribute(
    "aria-controls",
    "dashboard-pane-overview"
  )
  await capture(page, "dashboard-root-desktop")

  await page.setViewportSize({ width: 430, height: 1000 })
  await expect(page.locator("#operator-area-menu")).toBeVisible()
  await expectNoHorizontalOverflow(page, "#operator-area-menu")
  await capture(page, "dashboard-root-mobile")

  await page.goto("/repos")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#operator-app-shell")).toHaveAttribute("data-active-area", "repositories")
  await expect(page.getByRole("table", { name: "Managed repository inventory" })).toBeVisible()
  await capture(page, "repositories-inventory-mobile")

  await page.setViewportSize({ width: 1440, height: 1100 })
  await page.goto("/settings")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#operator-app-shell")).toHaveAttribute("data-active-area", "settings")
  await expect(page.locator("#settings-nav-github")).toHaveAttribute("aria-current", "page")
  await expect(page.locator("#settings-github-open-add-modal")).toBeVisible()
  await capture(page, "settings-github-desktop")
})

test("degraded Vue delivery keeps fallback panels accessible and product-oriented", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "fallback")
  await page.setViewportSize({ width: 1440, height: 1100 })
  await signIn(page, "/setup")

  const runtimeFallback = page.locator("#setup-runtime-defaults-widget-fallback")
  await expect(runtimeFallback).toHaveAttribute("role", "status")
  await expect(runtimeFallback).toHaveAttribute("aria-live", "polite")
  await expect(runtimeFallback).toHaveAttribute("data-vue-surface-delivery", "fallback")
  await expect(runtimeFallback).toContainText("Interactive runtime defaults panel temporarily unavailable")
  await expect(page.locator("#setup-start-path-selector-fallback")).toHaveAttribute("role", "status")
  await capture(page, "setup-fallback-desktop")

  await page.locator("#setup-start-choice-github-save").click()
  const repositoryFallback = page.locator("#setup-github-repository-selector-fallback")
  await expect(repositoryFallback).toHaveAttribute("role", "status")
  await expect(repositoryFallback).toHaveAttribute("aria-live", "polite")
  await expect(repositoryFallback).toContainText("Interactive GitHub repository picker temporarily unavailable")
  await expect(page.locator("#setup-github-repository-fallback-list")).toBeVisible()
  await capture(page, "setup-github-fallback-desktop")
})
