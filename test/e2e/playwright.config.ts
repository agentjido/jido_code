import path from "node:path"
import { defineConfig } from "@playwright/test"

const port = process.env.PLAYWRIGHT_PORT ?? "4101"
const baseURL = `http://localhost:${port}`
const repoRoot = path.resolve(__dirname, "../..")

export default defineConfig({
  testDir: ".",
  testMatch: ["*.spec.ts"],
  timeout: 60_000,
  fullyParallel: false,
  workers: 1,
  reporter: "list",
  outputDir: path.resolve(repoRoot, "tmp/playwright"),
  use: {
    baseURL,
    headless: true,
    viewport: { width: 1440, height: 1100 },
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    channel: "chrome",
  },
  webServer: {
    command: `bash -lc 'export MIX_ENV=test; PHX_SERVER=true PORT=${port} mix run --no-halt test/e2e/browser_server.exs'`,
    cwd: repoRoot,
    url: `${baseURL}/welcome`,
    reuseExistingServer: false,
    timeout: 120_000,
  },
})
