// covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
// covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
// covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
// covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
// covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
// covers: architecture.conversation_orchestration.route_level_runtime_readiness_and_continuity_are_operator_readable
// covers: architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned
// covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
// covers: architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented
import type { APIRequestContext, Page } from "@playwright/test"
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

test("repo detail keeps runtime readiness and clarification continuity readable across reload", async ({
  page,
  request
}) => {
  await prepareScenario(request, "conversation_ready")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-ready")

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

  await expect(page.locator("#project-detail-conversation-runtime-status")).toHaveText("Blocked")
  await expect(page.locator("#project-detail-conversation-runtime-notice")).toBeVisible()
  await expect(page.locator("#project-detail-conversation-runtime-notice-type")).toContainText(
    "conversation_runtime_workspace_unavailable"
  )
  await expect(page.locator("#project-detail-conversation-runtime-workspace")).toHaveText(
    "Workspace path unavailable"
  )
})

test("repo detail falls back to snapshot continuity when live conversation delivery degrades", async ({
  page,
  request
}) => {
  await prepareScenario(request, "conversation_degraded")
  await signIn(page, "/workbench")
  await openRepoDetailFromWorkbench(page, "owner/browser-conversation-degraded")

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
