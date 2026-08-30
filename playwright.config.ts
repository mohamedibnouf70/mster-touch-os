import { defineConfig, devices } from "@playwright/test";
import { loadEnvConfig } from "@next/env";

loadEnvConfig(process.cwd());

const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";

// Deterministic E2E must NOT attach to `next dev` (HMR/Fast Refresh aborts navigations
// with net::ERR_ABORTED and inflates cold-compile latency under Turbopack/OneDrive).
// Prefer a production server. Build via `npm run test:e2e` (or pre-build) before start.
const reuseExistingServer = process.env.E2E_REUSE_SERVER !== "0";

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  workers: 1,
  // Stateful happy path must not retry mid-flow against partial fixtures.
  retries: 0,
  timeout: 180_000,
  expect: { timeout: 20_000 },
  use: {
    baseURL,
    trace: "retain-on-failure",
    video: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  webServer: {
    command: process.env.E2E_WEB_SERVER_COMMAND ?? "npm run start",
    url: baseURL,
    reuseExistingServer,
    timeout: 180_000,
  },
});
