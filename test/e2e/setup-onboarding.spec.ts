// covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
// covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
// covers: setup.onboarding.post_bootstrap_start_surface
// covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
// covers: setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
import { mkdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import type { APIRequestContext } from "@playwright/test"
import { expect, test, type Page } from "@playwright/test"

const workspaceRoot = join(tmpdir(), "jido-code-browser-workspaces")

async function waitForLiveViewConnection(page: Page) {
  await page.waitForFunction(() => {
    const liveSocket = (window as Window & { liveSocket?: { isConnected?: () => boolean } }).liveSocket
    return typeof liveSocket?.isConnected === "function" && liveSocket.isConnected()
  })
}

async function prepareScenario(request: APIRequestContext, mode: "normal" | "fallback") {
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

async function signIn(page: Page) {
  await page.goto("/_test/browser/sign-in?to=/setup")
  await page.waitForURL(url => url.pathname === "/setup")
  await waitForLiveViewConnection(page)
}

test("rich setup widgets stay interactive inside the LiveView-owned setup route", async ({ page, request }) => {
  await prepareScenario(request, "normal")
  mkdirSync(workspaceRoot, { recursive: true })
  await signIn(page)

  await expect(page.locator("#setup-runtime-environment-select")).toBeVisible()
  await page.selectOption("#setup-runtime-environment-select", "local")
  await expect(page.locator("#setup-runtime-workspace-root")).toBeVisible()

  await page.fill("#setup-runtime-workspace-root", workspaceRoot)
  await page.click("#setup-runtime-environment-save")

  await expect(page.locator("#setup-saved-runtime-environment")).toHaveText("Local")
  await expect(page.locator("#setup-saved-runtime-note")).toContainText(workspaceRoot)

  await page.click("#setup-start-choice-github-save")

  await expect(page.locator("#setup-github-repository-widget-title")).toHaveText("Choose a GitHub repository")
  await expect(page.locator("#setup-github-repository-summary")).toHaveCount(0)
  await expect(page.locator("#setup-github-repository-widget-boundary-note")).toContainText(
    "LiveView still owns PAT capture, persistence, and completion"
  )

  await page.fill("#setup-github-repository-widget-search", "repo-two")
  await expect(page.locator("#setup-github-repository-widget-card-repo_100")).toHaveCount(0)
  await expect(page.locator("#setup-github-repository-widget-card-repo_200")).toBeVisible()

  await page.click("#setup-github-repository-widget-card-repo_200")
  await page.click("#setup-github-repository-widget-import")

  await expect(page.locator("#setup-github-repository-widget-import-status")).toHaveText("Imported")
  await expect(page.locator("#setup-github-repository-widget-import-detail")).toContainText("owner/repo-two")
  await expect(page.locator("#setup-github-repository-widget-open-repo")).toBeVisible()
})

test("fallback setup controls stay navigable when richer delivery degrades", async ({ page, request }) => {
  await prepareScenario(request, "fallback")
  await signIn(page)

  await expect(page.locator("#setup-runtime-defaults-widget-fallback")).toBeVisible()
  await expect(page.locator("#setup-start-path-selector-fallback")).toBeVisible()

  await page.click("#setup-start-choice-github-save")
  await expect(page.locator("#setup-selected-start-path")).toHaveText("Connect GitHub")

  await expect(page.locator("#setup-github-repository-selector-fallback")).toBeVisible()
  await expect(page.locator("#setup-github-repository-fallback-title")).toHaveText("Choose a GitHub repository")
  await expect(page.locator("#setup-github-repository-fallback-list")).toBeVisible()

  await page.click("#setup-github-repository-fallback-option-repo_200")
  await page.click("#setup-github-repository-fallback-import")

  await expect(page.locator("#setup-github-import-fallback-success")).toContainText(
    "Imported owner/repo-two into the managed-repository control plane."
  )
})
