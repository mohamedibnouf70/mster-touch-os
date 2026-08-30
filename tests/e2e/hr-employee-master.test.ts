/**
 * Phase 4.1 — HR Employee Master E2E
 *
 * Happy path: HR Manager onboard → detail → employment update → department →
 * compliance → directory → projects → deactivate/reactivate.
 *
 * Security: engineer denied org-wide HR; self vs peer compliance.
 *
 * Requires LIVE_TEST_ENABLED + Supabase env + migration 052 applied.
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

type HrFixture = {
  runId: string;
  orgId: string;
  projectId: string;
  hr: { email: string; password: string; userId: string; employeeId: string };
  engineer: { email: string; password: string; userId: string; employeeId: string };
  departmentId: string;
  onboardedEmployeeId: string | null;
};

async function createHrE2EFixture(runId: string): Promise<HrFixture> {
  const admin = adminClient();
  const prefix = process.env.E2E_PASSWORD ?? "E2eTest1!";

  await requireData(
    admin.from("organizations").select("id").eq("id", ORG_ID).single(),
    "ORG_ID must exist",
  );

  const { data: perm } = await admin
    .from("permissions")
    .select("key")
    .eq("key", "employee.create")
    .maybeSingle();
  if (!perm?.key) {
    throw new Error("Migration 052 required: employee.create permission missing. Apply phase4_fix_052.sql");
  }

  async function roleId(code: string) {
    const role = await requireData(
      admin.from("roles").select("id").eq("code", code).is("organization_id", null).single(),
      `role ${code}`,
    );
    return role.id;
  }

  async function provision(key: "hr" | "engineer", roleCode: string) {
    const email = `e2e-${key}-${runId}@test.local`;
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
          employee_number: `E2E-${key}-${runId}`.slice(0, 32),
        })
        .select("id")
        .single(),
      `employee ${key}`,
    );

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

    return { email, password, userId, employeeId: emp.id as string };
  }

  const hr = await provision("hr", "hr_manager");
  const engineer = await provision("engineer", "engineer");

  const project = await requireData(
    admin
      .from("projects")
      .insert({
        organization_id: ORG_ID,
        project_code: `E2E-HR-${runId}`,
        name_ar: `مشروع موارد ${runId}`,
        name_en: `HR E2E Project ${runId}`,
        status: "active",
        priority: "medium",
        progress_percentage: 0,
        risk_level: "low",
        created_by: hr.userId,
      })
      .select("id")
      .single(),
    "hr e2e project",
  );

  // HR must be able to access the project to read project_members via RLS
  // (can_access_project). Does not grant org-wide project.read.
  await requireData(
    admin
      .from("project_members")
      .upsert(
        {
          organization_id: ORG_ID,
          project_id: project.id,
          profile_id: hr.userId,
          role_label: "hr",
          is_active: true,
        },
        { onConflict: "project_id,profile_id" },
      )
      .select("id")
      .single(),
    "hr project member",
  );

  const department = await requireData(
    admin
      .from("departments")
      .insert({
        organization_id: ORG_ID,
        code: `E2E-HR-${runId}`,
        name_ar: `إدارة E2E ${runId}`,
        name_en: `E2E Dept ${runId}`,
        is_active: true,
      })
      .select("id")
      .single(),
    "hr e2e department",
  );

  return {
    runId,
    orgId: ORG_ID,
    projectId: project.id,
    hr,
    engineer,
    departmentId: department.id,
    onboardedEmployeeId: null,
  };
}

async function cleanupHrFixture(fx: HrFixture | null) {
  if (!fx) return;
  const admin = adminClient();
  await admin.from("projects").delete().eq("id", fx.projectId);
  await admin.from("departments").delete().eq("id", fx.departmentId);
  const emails = [fx.hr.email, fx.engineer.email];
  if (fx.onboardedEmployeeId) {
    const { data: emp } = await admin
      .from("employees")
      .select("profile_id")
      .eq("id", fx.onboardedEmployeeId)
      .maybeSingle();
    if (emp?.profile_id) {
      const { data: user } = await admin.auth.admin.getUserById(emp.profile_id);
      if (user?.user?.email) emails.push(user.user.email);
    }
  }
  const { data: listed } = await admin.auth.admin.listUsers({ perPage: 1000 });
  for (const email of emails) {
    const match = listed?.users.find((u) => u.email === email);
    if (match) await admin.auth.admin.deleteUser(match.id);
  }
}

test.describe("Phase 4.1 HR employee master", () => {
  test.describe.configure({ mode: "serial", retries: 0 });
  test.skip(!ENABLED, "LIVE_TEST_ENABLED not set");

  let fx: HrFixture;

  test.beforeAll(async () => {
    const runId = crypto.randomUUID().slice(0, 8);
    fx = await createHrE2EFixture(runId);
  });

  test.afterAll(async () => {
    await cleanupHrFixture(fx ?? null);
  });

  test("01 — HR Manager creates employee", async ({ page }) => {
    await signInViaUI(page, fx.hr.email, fx.hr.password, "E2E hr");
    await gotoApp(page, `/employees`);
    await expectPageMarker(page, "employees-page");
    await assertAuthenticatedPage(page, "E2E hr");

    const email = `e2e-onboard-${fx.runId}@test.local`;
    const number = `ONB-${fx.runId}`;

    await page.getByTestId("employee-create-email").fill(email);
    await page.getByTestId("employee-create-number").fill(number);
    await page.getByTestId("employee-create-name-ar").fill(`موظف ${fx.runId}`);
    await page.getByTestId("employee-create-name-en").fill(`Employee ${fx.runId}`);
    await page.getByTestId("employee-create-title").fill("مهندس مشاريع");
    await page.getByTestId("employee-create-type").selectOption("permanent");
    await page.getByTestId("employee-create-department").selectOption({ value: fx.departmentId });

    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      page.getByTestId("employee-create-submit").click(),
    ]);

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const { data, error } = await admin
            .from("employees")
            .select("id, employee_number, is_active")
            .eq("organization_id", fx.orgId)
            .eq("employee_number", number)
            .maybeSingle();
          if (error) return `error:${error.message}`;
          return data?.id ?? null;
        },
        { intervals: [250, 500, 1000] },
      )
      .toBeTruthy();

    const emp = await requireData(
      admin
        .from("employees")
        .select("id, employee_number, is_active")
        .eq("organization_id", fx.orgId)
        .eq("employee_number", number)
        .single(),
      "onboarded employee",
    );
    expect(emp.is_active).toBe(true);
    fx.onboardedEmployeeId = emp.id;

    await gotoApp(page, `/employees`);
    await expect(page.getByTestId(`employee-link-${emp.id}`)).toBeVisible({ timeout: 30_000 });
  });

  test("02 — open detail, update employment, assign department", async ({ page }) => {
    expect(fx.onboardedEmployeeId).toBeTruthy();
    await signInViaUI(page, fx.hr.email, fx.hr.password, "E2E hr");
    await gotoApp(page, `/employees/${fx.onboardedEmployeeId}`);
    await expectPageMarker(page, "employee-detail-page");

    await page.getByTestId("employee-edit-title").fill(`مسمى محدث ${fx.runId}`);
    await page.getByTestId("employee-edit-type").selectOption("fixed_term");
    await page.getByTestId("employee-edit-status").selectOption("probation");
    await page.getByTestId("employee-edit-probation-end").fill("2026-12-01");
    await page.getByTestId("employee-edit-employment-submit").click();

    await page.getByTestId("employee-tab-organization").click();
    await expectPageMarker(page, "employee-org-card");
    await page.getByTestId("employee-assign-department").selectOption({ value: fx.departmentId });
    await page.getByTestId("employee-assign-department-submit").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin
            .from("employees")
            .select("job_title_ar, employment_type, employment_status")
            .eq("id", fx.onboardedEmployeeId!)
            .single(),
          "employment after edit",
        );
        return `${row.employment_type}:${row.employment_status}:${row.job_title_ar}`;
      })
      .toContain("fixed_term:probation");
  });

  test("03 — compliance + project membership + directory", async ({ page }) => {
    expect(fx.onboardedEmployeeId).toBeTruthy();
    const admin = adminClient();

    // Link onboarded profile to project via authoritative project_members
    const { data: emp } = await admin
      .from("employees")
      .select("profile_id")
      .eq("id", fx.onboardedEmployeeId!)
      .single();
    await requireData(
      admin
        .from("project_members")
        .upsert(
          {
            organization_id: fx.orgId,
            project_id: fx.projectId,
            profile_id: emp!.profile_id,
            role_label: "member",
            is_active: true,
          },
          { onConflict: "project_id,profile_id" },
        )
        .select("id")
        .single(),
      "project member for onboarded",
    );

    await signInViaUI(page, fx.hr.email, fx.hr.password, "E2E hr");
    await gotoApp(page, `/employees/${fx.onboardedEmployeeId}?tab=compliance`);
    await expectPageMarker(page, "employee-compliance-card");
    await page.getByTestId("compliance-iqama-number").fill(`IQ-${fx.runId}`);
    await page.getByTestId("compliance-iqama-expiry").fill("2027-06-30");
    await page.getByTestId("compliance-passport-number").fill(`PP-${fx.runId}`);
    await page.getByTestId("compliance-gosi").fill(`GOSI-${fx.runId}`);
    await Promise.all([
      page.waitForResponse(
        (res) => res.request().method() === "POST" && Boolean(res.request().headers()["next-action"]),
        { timeout: 90_000 },
      ),
      page.getByTestId("compliance-submit").click(),
    ]);

    await gotoApp(page, `/employees/${fx.onboardedEmployeeId}?tab=projects`);
    await expectPageMarker(page, "employee-projects-card");
    await expect(page.getByText(new RegExp(`E2E-HR-${fx.runId}|مشروع موارد`))).toBeVisible({
      timeout: 20_000,
    });

    await gotoApp(page, `/employees`);
    await expect(page.getByTestId(`employee-row-${fx.onboardedEmployeeId}`)).toBeVisible();
  });

  test("04 — deactivate / reactivate preserves record", async ({ page }) => {
    expect(fx.onboardedEmployeeId).toBeTruthy();
    await signInViaUI(page, fx.hr.email, fx.hr.password, "E2E hr");
    await gotoApp(page, `/employees/${fx.onboardedEmployeeId}`);
    await expectPageMarker(page, "employee-detail-page");

    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      page.getByTestId("employee-toggle-active").click(),
    ]);

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("employees").select("is_active").eq("id", fx.onboardedEmployeeId!).single(),
          "after deactivate",
        );
        return row.is_active;
      })
      .toBe(false);

    await gotoApp(page, `/employees/${fx.onboardedEmployeeId}`);
    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      page.getByTestId("employee-toggle-active").click(),
    ]);

    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("employees").select("is_active").eq("id", fx.onboardedEmployeeId!).single(),
          "after reactivate",
        );
        return row.is_active;
      })
      .toBe(true);
  });

  test("05 — engineer denied org-wide directory; peer compliance denied", async ({ page }) => {
    await signInViaUI(page, fx.engineer.email, fx.engineer.password, "E2E engineer");
    await gotoApp(page, `/employees`);
    // Engineers without employee.read are redirected away from directory
    await expect(page).not.toHaveURL(/\/employees\/?$/);

    if (fx.onboardedEmployeeId) {
      await gotoApp(page, `/employees/${fx.onboardedEmployeeId}?tab=compliance`);
      await expect(page.getByTestId("employee-compliance-card")).toHaveCount(0);
    }

    // Self detail should work
    await gotoApp(page, `/employees/${fx.engineer.employeeId}`);
    await expectPageMarker(page, "employee-detail-page");
  });
});
