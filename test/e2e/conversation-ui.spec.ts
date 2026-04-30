// covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
// covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
// covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
// covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
// covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
// covers: architecture.conversation_orchestration.route_level_runtime_readiness_and_continuity_are_operator_readable
// covers: architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned
// covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
// covers: architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented
import type { APIRequestContext, Locator, Page } from "@playwright/test"
import { expect, test } from "@playwright/test"

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
  await page.goto(`/_test/browser/sign-in?to=${encodeURIComponent(destination)}`)
  await page.waitForURL(url => url.pathname === destination)
  await waitForLiveViewConnection(page)
}

async function openRepoDetailFromWorkbench(page: Page, githubFullName: string) {
  const repoRow = page.locator("tr", { hasText: githubFullName })
  await expect(repoRow).toBeVisible()
  await repoRow.getByRole("link", { name: /^Repo detail$/ }).first().click()
  await page.waitForURL(url => url.pathname.startsWith("/repos/"))
  await waitForLiveViewConnection(page)
}

async function expectRepoDetailRoute(page: Page, subject: string, section: string) {
  await page.waitForURL(url => {
    if (!url.pathname.startsWith("/repos/")) {
      return false
    }

    return (
      url.searchParams.get("subject") === subject &&
      url.searchParams.get("section") === section
    )
  })
}

async function openConversationFamily(page: Page) {
  await page.click("#project-detail-shell-parent-subjects-work")
  await expectRepoDetailRoute(page, "work", "conversations")
}

async function requiredBox(locator: Locator) {
  const box = await locator.boundingBox()

  if (!box) {
    throw new Error("expected locator to have a visible bounding box")
  }

  return box
}

test("repo detail keeps runtime readiness and clarification continuity readable across reload", async ({
  page,
  request
}) => {
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-ready")
  await openConversationFamily(page)

  await expect(page.locator("#project-detail-conversation-runtime-status")).toHaveText("Ready")
  await expect(page.locator("#project-detail-conversation-runtime-llm")).toContainText("openai:gpt-5-mini")
  await expect(page.locator("#project-detail-conversation-runtime-source")).toHaveText(
    "Managed repo default"
  )

  await page.click("#project-detail-conversation-open")
  await expect(page.locator("#project-detail-conversation-id")).toBeVisible()

  await page.fill("#project-detail-conversation-input", "Clarify which file needs input.")
  await page.click("#project-detail-conversation-submit")

  await expect(page.locator("#project-detail-conversation-pending-clarification")).toBeVisible()
  await expect(page.locator("#project-detail-conversation-turn-state")).toHaveText(
    "Clarification required"
  )
  await expect(page.locator("#project-detail-conversation-events")).toContainText(
    "Waiting for clarification before continuing."
  )

  await page.reload()
  await waitForLiveViewConnection(page)
  await page.click("#project-detail-conversation-open")

  await expect(page.locator("#project-detail-conversation-pending-clarification")).toBeVisible()
  await expect(page.locator("#project-detail-conversation-turn-state")).toHaveText(
    "Clarification required"
  )
})

test("repo detail exposes blocked runtime readiness without pretending execution can proceed", async ({
  page,
  request
}) => {
  await prepareScenario(request, "conversation_runtime_blocked")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-blocked")
  await openConversationFamily(page)

  await expect(page.locator("#project-detail-conversation-runtime-status")).toHaveText("Blocked")
  await expect(page.locator("#project-detail-conversation-runtime-notice")).toBeVisible()
  await expect(page.locator("#project-detail-conversation-runtime-notice-type")).toContainText(
    "conversation_runtime_workspace_binding_unavailable"
  )
  await expect(page.locator("#project-detail-conversation-runtime-workspace")).toHaveText(
    "No repo-scoped local workspace path saved"
  )
  await expect(page.locator("#project-detail-conversation-runtime-notice")).toContainText(
    "Repair workspace binding"
  )

  await page.click("#project-detail-conversation-runtime-repair")
  await expect(page.locator("#project-detail-overview-panel")).toBeVisible()
  await expect(page.locator("#project-detail-workspace-binding-panel")).toBeVisible()
})

test("repo detail falls back to snapshot continuity when live conversation delivery degrades", async ({
  page,
  request
}) => {
  await prepareScenario(request, "conversation_degraded")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-degraded")
  await openConversationFamily(page)

  await page.click("#project-detail-conversation-open")

  await expect(page.locator("#project-detail-conversation-degraded")).toBeVisible()
  await expect(page.locator("#project-detail-conversation-stream-mode")).toContainText("Snapshot only")
  await expect(page.locator("#project-detail-conversation-continuity-detail")).toContainText(
    "live delivery is unavailable"
  )
  await expect(page.locator("#project-detail-conversation-sequence-summary")).toContainText(
    "Sequence 0"
  )
})

test("repo detail keeps desktop subject navigation on the left while panes switch in place", async ({
  page,
  request
}) => {
  await page.setViewportSize({ width: 1440, height: 1200 })
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-ready")

  const sidebar = page.locator("#project-detail-section-sidebar")
  const content = page.locator("#project-detail-section-content")
  const parentRail = page.locator("#project-detail-shell-parent-subjects")
  const overviewLink = page.locator("#project-detail-section-nav-overview")
  const workChip = page.locator("#project-detail-shell-parent-subjects-work")

  await expect(page.locator("#project-detail-overview-panel")).toBeVisible()
  await expect(parentRail).toBeVisible()

  const sidebarBox = await requiredBox(sidebar)
  const contentBox = await requiredBox(content)

  expect(sidebarBox.x).toBeLessThan(contentBox.x)
  await expect(overviewLink).toBeVisible()

  await workChip.click()
  await expectRepoDetailRoute(page, "work", "conversations")

  const conversationsLink = page.locator("#project-detail-section-nav-conversations")
  const workflowsLink = page.locator("#project-detail-section-nav-workflows")
  const conversationsBox = await requiredBox(conversationsLink)
  const workflowsBox = await requiredBox(workflowsLink)

  expect(Math.abs(workflowsBox.x - conversationsBox.x)).toBeLessThan(24)
  expect(workflowsBox.y).toBeGreaterThan(conversationsBox.y + 40)

  await workflowsLink.click()
  await expectRepoDetailRoute(page, "work", "workflows")
  await expect(page.locator("#project-detail-workflows-panel")).toBeVisible()
  await expect(page.locator("#project-detail-overview-panel")).toHaveCount(0)

  await conversationsLink.click()
  await expectRepoDetailRoute(page, "work", "conversations")
  await expect(page.locator("#project-detail-conversation-panel")).toBeVisible()
  await expect(page.locator("#project-detail-conversation-runtime-status")).toHaveText("Ready")
})

test("repo detail keeps narrow-screen subject navigation usable as a stacked fallback", async ({
  page,
  request
}) => {
  await page.setViewportSize({ width: 430, height: 900 })
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-ready")

  const parentRail = page.locator("#project-detail-shell-parent-subjects")
  const nav = page.locator("#project-detail-section-nav")
  const content = page.locator("#project-detail-section-content")
  const overviewLink = page.locator("#project-detail-section-nav-overview")
  const workChip = page.locator("#project-detail-shell-parent-subjects-work")

  await expect(parentRail).toBeVisible()
  await expect(nav).toBeVisible()

  const parentRailBox = await requiredBox(parentRail)
  const navBox = await requiredBox(nav)
  const contentBox = await requiredBox(content)

  expect(parentRailBox.y).toBeLessThan(navBox.y)
  expect(navBox.y).toBeLessThan(contentBox.y)
  await expect(overviewLink).toBeVisible()

  await workChip.click()
  await expectRepoDetailRoute(page, "work", "conversations")

  const conversationsLink = page.locator("#project-detail-section-nav-conversations")
  const workflowsLink = page.locator("#project-detail-section-nav-workflows")
  const conversationsBox = await requiredBox(conversationsLink)
  const workflowsBox = await requiredBox(workflowsLink)

  expect(Math.abs(workflowsBox.x - conversationsBox.x)).toBeLessThan(12)
  expect(workflowsBox.y).toBeGreaterThan(conversationsBox.y)

  await page.locator("#project-detail-shell-parent-subjects-knowledge").click()
  await expectRepoDetailRoute(page, "knowledge", "semantic")

  const memoryLink = page.locator("#project-detail-section-nav-memory")
  await memoryLink.click()

  await expectRepoDetailRoute(page, "knowledge", "memory")
  await expect(page.locator("#project-detail-memory-inspection")).toBeVisible()

  await page.locator("#project-detail-memory-open-semantic").click()

  await expectRepoDetailRoute(page, "knowledge", "semantic")
  await expect(page.locator("#project-detail-semantic-inspection")).toBeVisible()
})

test("workbench-origin repo detail links preserve the specialist parent route", async ({
  page,
  request
}) => {
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-ready")

  await expect(page.locator("#project-detail-breadcrumb-return")).toHaveAttribute("href", "/workbench")
  await expect(page.locator("#project-detail-breadcrumb-return")).toContainText("Workbench")
  await expect(page.locator("#project-detail-return-link")).toHaveAttribute("href", "/workbench")
  await expect(page.locator("#project-detail-return-link")).toContainText("Back to Workbench")

  await page.locator("#project-detail-return-link").click()
  await page.waitForURL(url => url.pathname === "/workbench")
  await waitForLiveViewConnection(page)
  await expect(page.locator("#workbench-route-role-label")).toContainText("Dense specialist mode")
})

test("repo detail memory recall links back to the canonical conversation route", async ({
  page,
  request
}) => {
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-ready")

  const repoUrl = new URL(page.url())

  await page.goto(
    `${repoUrl.pathname}?return_to=${encodeURIComponent("/workbench")}&subject=knowledge&section=memory`
  )
  await waitForLiveViewConnection(page)
  await expectRepoDetailRoute(page, "knowledge", "memory")

  await expect(page.locator("#project-detail-conversation-recall-list")).toBeVisible()
  await expect(page.locator("#project-detail-conversation-recall-item-1-summary")).toContainText(
    "Conversation requested clarification"
  )

  await page.locator("#project-detail-conversation-recall-item-1-conversation-link-1").click()

  await page.waitForURL(url => {
    if (!url.pathname.startsWith("/repos/")) {
      return false
    }

    return url.searchParams.get("section") === "conversations"
  })
  await expect(page.locator("#project-detail-conversation-panel")).toBeVisible()
})
