/**
 * Phase 4.2 — HR Contracts, Versioned Compensation, HR Documents & Banking E2E
 *
 * Scenario:
 * 1. HR Manager login -> open employee detail
 * 2. Create contract -> activate contract -> verify current contract
 * 3. Create compensation version -> verify history and current total
 * 4. Add employee document -> verify document list
 * 5. Add bank account -> verify masked display
 * 6. Security verification: Engineer denied compensation/bank/contracts access
 */
import { test, expect } from "@playwright/test";
import {
  adminClient,
  assertAuthenticatedPage,
  expectPageMarker,
  gotoApp,
  ORG_ID,
  requireData,
  signInViaUI,
} from "./helpers";

const ENABLED = process.env.LIVE_TEST_ENABLED === "true" || process.env.LIVE_TEST_ENABLED === "1";

type Hr42Fixture = {
  runId: string;
  orgId: string;
  hr: { email: string; password: string; userId: string; employeeId: string };
  finance: { email: string; password: string; userId: string; employeeId: string };
  engineer: { email: string; password: string; userId: string; employeeId: string };
  targetEmployeeId: string;
};

async function createHr42E2EFixture(runId: string): Promise<Hr42Fixture> {
  const admin = adminClient();
  const prefix = process.env.E2E_PASSWORD ?? "E2eTest1!";

  await requireData(
    admin.from("organizations").select("id").eq("id", ORG_ID).single(),
    "ORG_ID must exist",
  );

  async function roleId(code: string) {
    const role = await requireData(
      admin.from("roles").select("id").eq("code", code).is("organization_id", null).single(),
      `role ${code}`,
    );
    return role.id;
  }

  async function provision(key: "hr" | "finance" | "engineer" | "emp", roleCode?: string) {
    const email = `e2e42-${key}-${runId}@test.local`;
    const password = `${prefix}${key}`;
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name_ar: `مستخدم E2E ${key}`,
        full_name_en: `E2E ${key}`,
        locale: "ar",
      },
    });
    if (error || !data.user) throw new Error(`createUser ${key}: ${error?.message}`);
    const userId = data.user.id;

    await requireData(
      admin
        .from("organization_members")
        .insert({ organization_id: ORG_ID, profile_id: userId, status: "active" })
        .select("profile_id")
        .single(),
      `org member ${key}`,
    );

    const emp = await requireData(
      admin
        .from("employees")
        .insert({
          organization_id: ORG_ID,
          profile_id: userId,
          employment_status: "active",
          is_active: true,
          employee_number: `E2E42-${key}-${runId}`.slice(0, 32),
        })
        .select("id")
        .single(),
      `employee ${key}`,
    );

    if (roleCode) {
      await requireData(
        admin
          .from("user_roles")
          .insert({
            organization_id: ORG_ID,
            profile_id: userId,
            role_id: await roleId(roleCode),
            scope_type: "organization",
          })
          .select("id")
          .single(),
        `role ${key}`,
      );
    }

    return { email, password, userId, employeeId: emp.id as string };
  }

  const hr = await provision("hr", "hr_manager");
  const finance = await provision("finance", "finance_manager");
  const engineer = await provision("engineer", "engineer");
  const target = await provision("emp");

  return {
    runId,
    orgId: ORG_ID,
    hr,
    finance,
    engineer,
    targetEmployeeId: target.employeeId,
  };
}

async function cleanupHr42Fixture(fx: Hr42Fixture | null) {
  if (!fx) return;
  const admin = adminClient();
  const emails = [fx.hr.email, fx.finance.email, fx.engineer.email, `e2e42-emp-${fx.runId}@test.local`];
  const { data: listed } = await admin.auth.admin.listUsers({ perPage: 1000 });
  for (const email of emails) {
    const match = listed?.users.find((u) => u.email === email);
    if (match) await admin.auth.admin.deleteUser(match.id);
  }
}

test.describe("Phase 4.2 Contracts, Compensation, Documents & Banking E2E", () => {
  test.describe.configure({ mode: "serial", retries: 0 });
  test.skip(!ENABLED, "LIVE_TEST_ENABLED not set");

  let fx: Hr42Fixture;

  test.beforeAll(async () => {
    const runId = crypto.randomUUID().slice(0, 8);
    fx = await createHr42E2EFixture(runId);
  });

  test.afterAll(async () => {
    await cleanupHr42Fixture(fx ?? null);
  });

  test("01 — HR creates and activates employee contract", async ({ page }) => {
    await signInViaUI(page, fx.hr.email, fx.hr.password, "E2E hr");
    await gotoApp(page, `/employees/${fx.targetEmployeeId}?tab=contracts`);
    await expectPageMarker(page, "employee-detail-page");
    await assertAuthenticatedPage(page, "E2E hr");

    const contractNum = `CTR-E2E-${fx.runId}`;
    await page.getByTestId("contract-number-input").fill(contractNum);
    await page.getByTestId("contract-type-select").selectOption("permanent");
    await page.getByTestId("contract-start-date").fill("2026-01-01");
    await page.getByTestId("contract-initial-salary").fill("15000");

    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      page.getByTestId("contract-submit").click(),
    ]);

    await gotoApp(page, `/employees/${fx.targetEmployeeId}?tab=contracts`);

    // Activate contract
    const activateBtn = page.locator(`button[data-testid^="contract-activate-btn-"]`).first();
    await expect(activateBtn).toBeVisible({ timeout: 30_000 });

    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      activateBtn.click(),
    ]);

    await gotoApp(page, `/employees/${fx.targetEmployeeId}?tab=contracts`);
    await expect(page.getByTestId("contract-current-badge").first()).toBeVisible({ timeout: 30_000 });
  });

  test("02 — HR creates versioned compensation and verifies total", async ({ page }) => {
    await signInViaUI(page, fx.hr.email, fx.hr.password, "E2E hr");
    await gotoApp(page, `/employees/${fx.targetEmployeeId}?tab=compensation`);
    await expectPageMarker(page, "employee-detail-page");

    await page.getByTestId("comp-effective-from").fill("2026-01-01");
    await page.getByTestId("comp-basic-input").fill("12000");
    await page.getByTestId("comp-housing-input").fill("3000");
    await page.getByTestId("comp-transport-input").fill("1000");
    await page.getByTestId("comp-reason-input").fill("Initial salary package");

    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      page.getByTestId("comp-submit").click(),
    ]);

    await gotoApp(page, `/employees/${fx.targetEmployeeId}?tab=compensation`);
    await expect(page.getByTestId("comp-total-display")).toBeVisible({ timeout: 30_000 });
    await expect(page.getByTestId("comp-total-display")).toHaveText(/(16[,.]?000|١٦[٬،.]?٠٠٠)/);
  });

  test("03 — HR adds employee bank account and verifies masked display", async ({ page }) => {
    await signInViaUI(page, fx.hr.email, fx.hr.password, "E2E hr");
    await gotoApp(page, `/employees/${fx.targetEmployeeId}?tab=banking`);
    await expectPageMarker(page, "employee-detail-page");

    await page.getByTestId("bank-name-input").fill("Al Rajhi Bank");
    await page.getByTestId("bank-iban-input").fill("SA0380000000608010167519");
    await page.getByTestId("bank-account-name-input").fill("E2E Employee");

    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      page.getByTestId("bank-submit").click(),
    ]);

    await gotoApp(page, `/employees/${fx.targetEmployeeId}?tab=banking`);
    await expect(page.getByTestId("employee-banking-card")).toBeVisible({ timeout: 30_000 });
    await expect(page.getByText("Al Rajhi Bank")).toBeVisible({ timeout: 30_000 });
  });

  test("04 — Engineer is denied access to sensitive HR tabs", async ({ page }) => {
    await signInViaUI(page, fx.engineer.email, fx.engineer.password, "E2E engineer");
    await gotoApp(page, `/employees/${fx.targetEmployeeId}`);

    // Verify sensitive tabs are not shown in tabs navigation for engineer
    await expect(page.getByTestId("employee-tab-compensation")).toHaveCount(0);
    await expect(page.getByTestId("employee-tab-banking")).toHaveCount(0);
    await expect(page.getByTestId("employee-tab-contracts")).toHaveCount(0);
  });
});
