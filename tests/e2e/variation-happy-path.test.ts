/**
 * Variation Happy Path E2E (Phase 3.2)
 *
 * Optional RFI seed → variation → submit → partial approval (70,000 of 100,000).
 * Original contract_value stays unchanged; commercial summary includes approved amount only.
 *
 * Requires LIVE_TEST_ENABLED=true and the same Supabase env as procurement E2E.
 */
import { test, expect } from "@playwright/test";
import {
  adminClient,
  assertAuthenticatedPage,
  cleanupE2EFixture,
  createE2EFixture,
  expectPageMarker,
  requireData,
  signInApiClient,
  signInViaUI,
  type E2EFixture,
} from "./helpers";

const ENABLED = process.env.LIVE_TEST_ENABLED === "true" || process.env.LIVE_TEST_ENABLED === "1";
const ORIGINAL_CONTRACT_VALUE = 500_000;
const REQUESTED_AMOUNT = 100_000;
const APPROVED_AMOUNT = 70_000;

test.describe("Variation Happy Path", () => {
  test.describe.configure({ mode: "serial", retries: 0 });
  test.skip(!ENABLED, "LIVE_TEST_ENABLED not set");

  let fx: E2EFixture;
  let contractId: string;
  let rfiId: string | null = null;
  let variationId: string;

  test.beforeAll(async () => {
    const runId = crypto.randomUUID().slice(0, 8);
    fx = await createE2EFixture(runId);

    const admin = adminClient();
    const contract = await requireData(
      admin
        .from("project_contracts")
        .insert({
          organization_id: fx.orgId,
          project_id: fx.projectId,
          client_name: `VO Client ${fx.runId}`,
          contract_number: `CON-VO-${fx.runId}`,
          contract_value: ORIGINAL_CONTRACT_VALUE,
          currency: "SAR",
          retention_percent: 0,
          status: "active",
          created_by: fx.userIds.finance,
        })
        .select("id")
        .single(),
      "variation-suite contract",
    );
    contractId = contract.id;
  });

  test.afterAll(async () => {
    await cleanupE2EFixture(fx ?? null);
  });

  test("01 — Admin seeds RFI via service role (or continues on project)", async () => {
    const admin = adminClient();
    const { data: rpcDoc, error: rpcErr } = await admin.rpc("register_controlled_document", {
      p_organization_id: fx.orgId,
      p_project_id: fx.projectId,
      p_type_code: "RFI",
      p_discipline_code: "GENERAL",
      p_title: `E2E RFI ${fx.runId}`,
      p_confidentiality: "internal",
    });

    let documentId: string | null = null;
    let rfiNumber = `RFI-E2E-${fx.runId}`;
    const rpcRow = rpcDoc as { id?: string; document_number?: string } | null;
    if (!rpcErr && rpcRow?.id) {
      documentId = rpcRow.id;
      if (rpcRow.document_number) rfiNumber = rpcRow.document_number;
    } else {
      const { data: doc, error: docErr } = await admin
        .from("documents")
        .insert({
          organization_id: fx.orgId,
          project_id: fx.projectId,
          category: "rfi",
          title: `E2E RFI ${fx.runId}`,
          uploaded_by: fx.userIds.approver,
          created_by: fx.userIds.approver,
        })
        .select("id")
        .single();
      if (!docErr && doc?.id) documentId = doc.id;
    }

    if (!documentId) {
      rfiId = null;
      return;
    }

    const { data: rfi, error } = await admin
      .from("rfis")
      .insert({
        organization_id: fx.orgId,
        project_id: fx.projectId,
        document_id: documentId,
        rfi_number: rfiNumber,
        subject: `E2E variation source ${fx.runId}`,
        question: `هل يلزم أمر تغيير لهذا الاختبار ${fx.runId}؟`,
        raised_by: fx.userIds.engineer,
        responsible_engineer_id: fx.userIds.engineer,
        status: "submitted",
        created_by: fx.userIds.approver,
      })
      .select("id")
      .single();

    rfiId = error ? null : (rfi?.id ?? null);
    expect(fx.projectId).toBeTruthy();
  });

  test("02 — Approver (PM stand-in) creates variation linked to project", async ({ page }) => {
    await signInViaUI(page, fx.users.approver, fx.passwords.approver, "E2E approver");
    await page.goto(`/finance/variations/new?projectId=${fx.projectId}`);
    await expectPageMarker(page, "variation-create-page");
    await assertAuthenticatedPage(page, "E2E approver");

    await page.getByTestId("variation-project").selectOption({ value: fx.projectId });
    const contractSelect = page.locator('select[name="contractId"]');
    if (await contractSelect.count()) {
      await contractSelect.selectOption({ value: contractId }).catch(() => undefined);
    }
    await page.getByTestId("variation-source").selectOption({ value: rfiId ? "rfi" : "client_instruction" });
    await page
      .getByTestId("variation-description")
      .fill(`أمر تغيير E2E مرتبط بالمشروع ${fx.runId}${rfiId ? ` RFI ${rfiId}` : ""}`);
    await page.getByTestId("variation-amount").fill(String(REQUESTED_AMOUNT));

    await Promise.all([
      page.waitForURL(/\/finance\/variations\/?$/, { timeout: 60_000 }),
      page.getByTestId("variation-submit").click(),
    ]);

    const admin = adminClient();
    const vo = await requireData(
      admin
        .from("variations")
        .select("id, status, requested_amount, project_id")
        .eq("organization_id", fx.orgId)
        .eq("project_id", fx.projectId)
        .ilike("description", `%${fx.runId}%`)
        .single(),
      "created variation",
    );
    expect(vo.status).toBe("draft");
    expect(vo.project_id).toBe(fx.projectId);
    expect(Number(vo.requested_amount)).toBe(REQUESTED_AMOUNT);
    variationId = vo.id;
  });

  test("03 — Submit variation for approval", async ({ page }) => {
    expect(variationId, "variationId from step 02").toBeTruthy();
    await signInViaUI(page, fx.users.approver, fx.passwords.approver, "E2E approver");
    await page.goto(`/finance/variations/${variationId}`);
    await expectPageMarker(page, "variation-detail-page");
    await expect(page.getByTestId("variation-approver")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("variation-approver").selectOption({ value: fx.userIds.approver });
    await page.getByTestId("variation-submit-button").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("variations").select("status").eq("id", variationId).single(),
          "variation after submit",
        );
        return row.status;
      })
      .toBe("under_review");
  });

  test("04 — Finance approves variation with partial amount 70000 of 100000", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/variations/${variationId}`);
    await expectPageMarker(page, "variation-detail-page");
    await expect(page.getByTestId("variation-approved-amount")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("variation-approved-amount").fill(String(APPROVED_AMOUNT));
    await page.getByTestId("variation-approve-submit").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("variations").select("status, approved_amount").eq("id", variationId).single(),
          "variation after approve",
        );
        return row.status;
      })
      .toBe("partially_approved");
  });

  test("05 — Assert original contract_value unchanged", async () => {
    const admin = adminClient();
    const contract = await requireData(
      admin.from("project_contracts").select("contract_value").eq("id", contractId).single(),
      "contract after VO",
    );
    expect(Number(contract.contract_value)).toBe(ORIGINAL_CONTRACT_VALUE);
  });

  test("06 — Assert variation is partially_approved at 70000", async () => {
    const admin = adminClient();
    const vo = await requireData(
      admin
        .from("variations")
        .select("status, requested_amount, submitted_amount, approved_amount")
        .eq("id", variationId)
        .single(),
      "variation final",
    );
    expect(vo.status).toBe("partially_approved");
    expect(Number(vo.requested_amount)).toBe(REQUESTED_AMOUNT);
    expect(Number(vo.approved_amount)).toBe(APPROVED_AMOUNT);
    expect(Number(vo.approved_amount)).toBeLessThan(Number(vo.requested_amount));
  });

  test("07 — Summary approved_variations includes approved amount only", async () => {
    const finance = await signInApiClient(fx.users.finance, fx.passwords.finance);
    const { data: summary, error } = await finance.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(error).toBeNull();
    const row = summary as {
      approved_variations?: number;
      original_contract_value?: number;
      revised_contract_value?: number;
    };
    expect(Number(row.approved_variations ?? 0)).toBe(APPROVED_AMOUNT);
    expect(Number(row.approved_variations ?? 0)).toBeLessThan(REQUESTED_AMOUNT);
    expect(Number(row.original_contract_value ?? 0)).toBe(ORIGINAL_CONTRACT_VALUE);
  });

  test("08 — Revised contract value = original + approved only", async () => {
    const finance = await signInApiClient(fx.users.finance, fx.passwords.finance);
    const { data: summary, error } = await finance.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(error).toBeNull();
    const row = summary as {
      approved_variations?: number;
      original_contract_value?: number;
      revised_contract_value?: number;
    };
    expect(Number(row.revised_contract_value)).toBe(ORIGINAL_CONTRACT_VALUE + APPROVED_AMOUNT);
    expect(Number(row.revised_contract_value)).not.toBe(ORIGINAL_CONTRACT_VALUE + REQUESTED_AMOUNT);
  });
});
