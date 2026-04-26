// covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
// covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
// covers: setup.onboarding.post_bootstrap_start_surface
// covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
// covers: setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
// covers: setup.onboarding.github_repository_selection_supports_account_filter_and_matching_search
import { mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { APIRequestContext } from "@playwright/test";
import { expect, test, type Page } from "@playwright/test";

const workspaceRoot = join(tmpdir(), "jido-code-browser-workspaces");

async function waitForLiveViewConnection(page: Page) {
  await page.waitForFunction(() => {
    const liveSocket = (
      window as Window & { liveSocket?: { isConnected?: () => boolean } }
    ).liveSocket;
    return (
      typeof liveSocket?.isConnected === "function" && liveSocket.isConnected()
    );
  });
}

async function prepareScenario(
  request: APIRequestContext,
  mode: "normal" | "fallback"
) {
  let lastResponse: Awaited<ReturnType<APIRequestContext["get"]>> | null = null;

  for (let attempt = 0; attempt < 5; attempt += 1) {
    lastResponse = await request.get(`/_test/browser/scenario?mode=${mode}`);

    if (lastResponse.ok()) {
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  throw new Error(
    `scenario ${mode} failed with status ${lastResponse?.status()} and body ${await lastResponse?.text()}`
  );
}

async function signIn(page: Page) {
  await page.goto("/_test/browser/sign-in?to=/setup");
  await page.waitForURL((url) => url.pathname === "/setup");
  await waitForLiveViewConnection(page);
}

async function expectLocatorsNotToOverlap(
  page: Page,
  firstSelector: string,
  secondSelector: string
) {
  const overlaps = await page.evaluate(
    ([first, second]) => {
      const firstElement = document.querySelector(first);
      const secondElement = document.querySelector(second);

      if (
        !(firstElement instanceof HTMLElement) ||
        !(secondElement instanceof HTMLElement)
      ) {
        return null;
      }

      const firstBox = firstElement.getBoundingClientRect();
      const secondBox = secondElement.getBoundingClientRect();

      return !(
        firstBox.right <= secondBox.left ||
        secondBox.right <= firstBox.left ||
        firstBox.bottom <= secondBox.top ||
        secondBox.bottom <= firstBox.top
      );
    },
    [firstSelector, secondSelector]
  );

  expect(overlaps).toBe(false);
}

async function expectLocatorWidthRatio(
  page: Page,
  containerSelector: string,
  contentSelector: string,
  minimumRatio: number
) {
  const ratio = await page.evaluate(
    ([container, content]) => {
      const containerElement = document.querySelector(container);
      const contentElement = document.querySelector(content);

      if (
        !(containerElement instanceof HTMLElement) ||
        !(contentElement instanceof HTMLElement)
      ) {
        return null;
      }

      const containerWidth = containerElement.getBoundingClientRect().width;
      const contentWidth = contentElement.getBoundingClientRect().width;

      if (containerWidth === 0) {
        return null;
      }

      return contentWidth / containerWidth;
    },
    [containerSelector, contentSelector]
  );

  expect(ratio).not.toBeNull();
  expect(ratio ?? 0).toBeGreaterThanOrEqual(minimumRatio);
}

test("rich setup widgets stay interactive inside the LiveView-owned setup route", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "normal");
  mkdirSync(workspaceRoot, { recursive: true });
  await page.setViewportSize({ width: 960, height: 1100 });
  await signIn(page);

  await expect(page.locator("#setup-runtime-environment-select")).toBeVisible();
  await page.selectOption("#setup-runtime-environment-select", "local");
  await expect(page.locator("#setup-runtime-workspace-root")).toBeVisible();

  await page.fill("#setup-runtime-workspace-root", workspaceRoot);
  await page.click("#setup-runtime-environment-save");

  await expect(page.locator("#setup-saved-runtime-environment")).toHaveText(
    "Local"
  );
  await expect(
    page.locator("#setup-runtime-defaults-description")
  ).toContainText(
    "Local defaults seed new imports from a workspace root on this machine"
  );
  await expect(page.locator("#setup-saved-runtime-note")).toContainText(
    workspaceRoot
  );

  await page.selectOption("#setup-runtime-environment-select", "cloud");
  await page.click("#setup-runtime-environment-save");

  await expect(page.locator("#setup-saved-runtime-environment")).toHaveText(
    "Cloud"
  );
  await expect(
    page.locator("#setup-runtime-defaults-description")
  ).toContainText("Cloud defaults keep new imports on Sprite-backed execution");
  await expect(page.locator("#setup-saved-runtime-note")).toContainText(
    "Cloud defaults map to Sprite-backed execution"
  );
  await expect(page.locator("#setup-runtime-workspace-root")).toHaveCount(0);

  await page.click("#setup-start-choice-github-save");

  await expect(
    page.locator("#setup-github-repository-widget-title")
  ).toHaveText("Choose GitHub repositories");
  await expect(page.locator("#setup-github-repository-summary")).toHaveCount(0);
  await expect(
    page.locator("#setup-github-repository-widget-boundary-note")
  ).toContainText(
    "LiveView still owns PAT capture, persistence, and completion"
  );
  await expectLocatorsNotToOverlap(
    page,
    "#setup-github-repository-widget-search",
    "#setup-github-repository-widget-import"
  );
  await expectLocatorWidthRatio(
    page,
    "#setup-github-repository-selector",
    "#setup-github-repository-widget-results",
    0.85
  );

  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toBeDisabled();
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toHaveText("Select repositories to import");

  await page.selectOption(
    "#setup-github-repository-widget-account-filter",
    "agentjido"
  );
  await expect(
    page.locator("#setup-github-repository-widget-card-repo_300")
  ).toBeVisible();
  await expect(
    page.locator("#setup-github-repository-widget-card-repo_100")
  ).toHaveCount(0);
  await expect(
    page.locator("#setup-github-repository-widget-card-repo_200")
  ).toHaveCount(0);

  await page.selectOption("#setup-github-repository-widget-account-filter", "");

  await page.click("#setup-github-repository-widget-card-repo_100");
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toBeEnabled();
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toHaveText("Import selected repository");

  await page.click("#setup-github-repository-widget-card-repo_100");
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toBeDisabled();
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toHaveText("Select repositories to import");

  await page.click("#setup-github-repository-widget-card-repo_100");
  await page.click("#setup-github-repository-widget-card-repo_200");
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toHaveText("Import 2 selected repositories");

  await page.click("#setup-github-repository-widget-card-repo_100");
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toHaveText("Import selected repository");

  await page.fill("#setup-github-repository-widget-search", "repo-two");
  await expect(
    page.locator("#setup-github-repository-widget-card-repo_100")
  ).toHaveCount(0);
  await expect(
    page.locator("#setup-github-repository-widget-card-repo_200")
  ).toBeVisible();

  await page.click("#setup-github-repository-widget-import");

  await expect(
    page.locator("#setup-github-repository-widget-import-status")
  ).toHaveText("Imported");
  await expect(
    page.locator("#setup-github-repository-widget-import-detail")
  ).toContainText("owner/repo-two");
  await expect(page.locator("text=Created managed repo")).toBeVisible();
  await expect(
    page.locator("#setup-github-repository-widget-selection")
  ).toHaveText("Not selected");
  await expect(
    page.locator("#setup-github-repository-widget-import")
  ).toBeDisabled();
  await expect(
    page.locator("#setup-github-repository-widget-open-repo")
  ).toBeVisible();
});

test("fallback setup controls stay navigable when richer delivery degrades", async ({
  page,
  request,
}) => {
  await prepareScenario(request, "fallback");
  await signIn(page);

  await expect(
    page.locator("#setup-runtime-defaults-widget-fallback")
  ).toBeVisible();
  await expect(
    page.locator("#setup-start-path-selector-fallback")
  ).toBeVisible();

  await page.click("#setup-start-choice-github-save");
  await expect(page.locator("#setup-selected-start-path")).toHaveText(
    "Connect GitHub"
  );

  await expect(
    page.locator("#setup-github-repository-selector-fallback")
  ).toBeVisible();
  await expect(
    page.locator("#setup-github-repository-fallback-title")
  ).toHaveText("Choose GitHub repositories");
  await expect(
    page.locator("#setup-github-repository-fallback-list")
  ).toBeVisible();

  await expect(
    page.locator("#setup-github-repository-fallback-import")
  ).toBeDisabled();
  await expect(
    page.locator("#setup-github-repository-fallback-import")
  ).toHaveText("Select repositories to import");

  await page.selectOption(
    "#setup-github-repository-fallback-account-filter",
    "agentjido"
  );
  await expect(
    page.locator("#setup-github-repository-fallback-option-repo_300")
  ).toBeVisible();
  await expect(
    page.locator("#setup-github-repository-fallback-option-repo_100")
  ).toHaveCount(0);
  await expect(
    page.locator("#setup-github-repository-fallback-option-repo_200")
  ).toHaveCount(0);

  await page.selectOption(
    "#setup-github-repository-fallback-account-filter",
    ""
  );
  await page.fill("#setup-github-repository-fallback-search", "repo-two");
  await expect(
    page.locator("#setup-github-repository-fallback-option-repo_100")
  ).toHaveCount(0);
  await expect(
    page.locator("#setup-github-repository-fallback-option-repo_200")
  ).toBeVisible();
  await expect(
    page.locator("#setup-github-repository-fallback-option-repo_300")
  ).toHaveCount(0);
  await page.fill("#setup-github-repository-fallback-search", "");

  await page.click("#setup-github-repository-fallback-option-repo_100");
  await expect(
    page.locator("#setup-github-repository-fallback-import")
  ).toHaveText("Import selected repository");

  await page.click("#setup-github-repository-fallback-option-repo_200");
  await expect(
    page.locator("#setup-github-repository-fallback-import")
  ).toHaveText("Import 2 selected repositories");

  await page.click("#setup-github-repository-fallback-import");

  await expect(
    page.locator("#setup-github-import-fallback-success")
  ).toContainText(
    "Imported 2 GitHub repositories into the managed-repository control plane."
  );
  await expect(
    page.locator("#setup-github-repository-fallback-selection")
  ).toHaveText("Not selected");
  await expect(
    page.locator("#setup-github-repository-fallback-import")
  ).toBeDisabled();
  await expect(
    page.locator("#setup-github-import-fallback-open-repo")
  ).toHaveCount(0);
});
