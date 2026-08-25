/**
 * Commercial security E2E (Phase 3.2)
 *
 * Engineer must not see finance / commercial contract surfaces, and must be
 * denied compute_project_commercial_summary (FORBIDDEN).
 *
 * Requires LIVE_TEST_ENABLED=true and the same Supabase env as procurement E2E.
 */
import { test, expect, type Page } from "@playwright/test";
import {
  assertAuthenticatedPage,
  cleanupE2EFixture,
  createE2EFixture,
  signInApiClient,
  signInViaUI,
  type E2EFixture,
} from "./helpers";

const ENABLED = process.env.LIVE_TEST_ENABLED === "true" || process.env.LIVE_TEST_ENABLED === "1";

const FORBIDDEN_TEXT = /ليست لديك صلاحية|غير مصرح|ممنوع|صلاحية|forbidden|unauthorized|access denied/i;

async function expectDeniedProtectedPage(page: Page, path: string, protectedTestId: string) {
  await page.goto(path);
  await assertAuthenticatedPage(page, "E2E engineer");
  await expect(page.getByTestId(protectedTestId)).toHaveCount(0);

  const url = new URL(page.url());
  const targetPath = new URL(path, page.url()).pathname.replace(/\/$/, "") || "/";
  const currentPath = url.pathname.replace(/\/$/, "") || "/";
  const redirectedAway = currentPath !== targetPath;
  const body = (await page.locator("body").innerText().catch(() => "")).slice(0, 2500);
  const forbiddenCopy = FORBIDDEN_TEXT.test(body);

  expect(
    redirectedAway || forbiddenCopy,
    `Engineer reached protected content at ${path}. url=${page.url()} body=${body.slice(0, 400)}`,
  ).toBeTruthy();
}

test.describe("Commercial security — engineer denied", () => {
  test.describe.configure({ mode: "serial", retries: 0 });
  test.skip(!ENABLED, "LIVE_TEST_ENABLED not set");

  let fx: E2EFixture;

  test.beforeAll(async () => {
    const runId = crypto.randomUUID().slice(0, 8);
    fx = await createE2EFixture(runId);
  });

  test.afterAll(async () => {
    await cleanupE2EFixture(fx ?? null);
  });

  test("01 — Engineer is denied /finance dashboard", async ({ page }) => {
    await signInViaUI(page, fx.users.engineer, fx.passwords.engineer, "E2E engineer");
    await expectDeniedProtectedPage(page, "/finance", "finance-dashboard-page");
  });

  test("02 — Engineer is denied /finance/client-valuations", async ({ page }) => {
    await signInViaUI(page, fx.users.engineer, fx.passwords.engineer, "E2E engineer");
    await expectDeniedProtectedPage(page, "/finance/client-valuations", "client-valuations-page");
  });

  test("03 — Engineer is denied /finance/client-invoices", async ({ page }) => {
    await signInViaUI(page, fx.users.engineer, fx.passwords.engineer, "E2E engineer");
    await expectDeniedProtectedPage(page, "/finance/client-invoices", "client-invoices-page");
  });

  test("04 — Engineer is denied project commercial contract page", async ({ page }) => {
    await signInViaUI(page, fx.users.engineer, fx.passwords.engineer, "E2E engineer");
    await expectDeniedProtectedPage(
      page,
      `/projects/${fx.projectId}/commercial/contract`,
      "project-contract-page",
    );
  });

  test("05 — Engineer RPC compute_project_commercial_summary is FORBIDDEN", async () => {
    const engineer = await signInApiClient(fx.users.engineer, fx.passwords.engineer);
    const { data, error } = await engineer.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(data).toBeFalsy();
    expect(error?.message ?? "").toMatch(/FORBIDDEN/i);
  });
});
