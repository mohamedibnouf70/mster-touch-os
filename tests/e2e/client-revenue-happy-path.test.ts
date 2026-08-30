/**
 * Client Revenue Happy Path E2E (Phase 3.2)
 *
 * Contract → milestone → valuation → internal review/approve →
 * client certification (partial) → invoice → issue → partial/final payment (PAID).
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
  signInViaUI,
  type E2EFixture,
} from "./helpers";

const ENABLED = process.env.LIVE_TEST_ENABLED === "true" || process.env.LIVE_TEST_ENABLED === "1";
const CONTRACT_VALUE = 500_000;
const GROSS_WORK = 100_000;
const CERTIFIED_AMOUNT = 80_000;

test.describe("Client Revenue Happy Path", () => {
  test.describe.configure({ mode: "serial", retries: 0, timeout: 180_000 });
  test.skip(!ENABLED, "LIVE_TEST_ENABLED not set");

  let fx: E2EFixture;
  let contractId: string;
  let milestoneId: string;
  let valuationId: string;
  let invoiceId: string;

  test.beforeAll(async () => {
    const runId = crypto.randomUUID().slice(0, 8);
    fx = await createE2EFixture(runId);
  });

  test.afterAll(async () => {
    await cleanupE2EFixture(fx ?? null);
  });

  test("01 — Finance creates project contract", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/projects/${fx.projectId}/commercial/contract`);
    await expectPageMarker(page, "project-contract-page");
    await assertAuthenticatedPage(page, "E2E finance");

    await page.getByTestId("contract-client-name").fill(`عميل E2E ${fx.runId}`);
    await page.getByTestId("contract-number").fill(`CON-E2E-${fx.runId}`);
    await page.getByTestId("contract-value").fill(String(CONTRACT_VALUE));
    await page.locator('[name="retentionPercent"]').fill("0");
    await Promise.all([
      page.waitForResponse(
        (res) => {
          const req = res.request();
          return req.method() === "POST" && Boolean(req.headers()["next-action"]);
        },
        { timeout: 90_000 },
      ),
      page.getByTestId("contract-create-submit").click(),
    ]);

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const { data } = await admin
            .from("project_contracts")
            .select("id")
            .eq("organization_id", fx.orgId)
            .eq("project_id", fx.projectId)
            .eq("contract_number", `CON-E2E-${fx.runId}`)
            .maybeSingle();
          return data?.id ?? null;
        },
        { timeout: 60_000 },
      )
      .toBeTruthy();

    const row = await requireData(
      admin
        .from("project_contracts")
        .select("id, status, contract_value")
        .eq("organization_id", fx.orgId)
        .eq("project_id", fx.projectId)
        .eq("contract_number", `CON-E2E-${fx.runId}`)
        .single(),
      "created contract",
    );
    expect(Number(row.contract_value)).toBe(CONTRACT_VALUE);
    expect(row.status).toBe("draft");
    contractId = row.id;
    expect(contractId, "contractId").toBeTruthy();
  });

  test("02 — Finance activates contract", async ({ page }) => {
    expect(contractId, "contractId from step 01").toBeTruthy();
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/projects/${fx.projectId}/commercial/contract`);
    await expectPageMarker(page, "project-contract-page");
    await expect(page.getByTestId("contract-activate-submit")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("contract-activate-submit").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("project_contracts").select("status").eq("id", contractId).single(),
          "contract after activate",
        );
        return row.status;
      })
      .toBe("active");
  });

  test("03 — Finance creates payment milestone", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/projects/${fx.projectId}/commercial/milestones`);
    await expectPageMarker(page, "project-milestones-page");

    await page.getByTestId("milestone-name").fill(`مرحلة E2E ${fx.runId}`);
    await page.getByTestId("milestone-description").fill(`وصف مرحلة اختبار ${fx.runId}`);
    await page.getByTestId("milestone-amount").fill(String(GROSS_WORK));
    await page.getByTestId("milestone-create-submit").click();

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const { data } = await admin
            .from("contract_milestones")
            .select("id")
            .eq("contract_id", contractId)
            .ilike("name", `%${fx.runId}%`)
            .maybeSingle();
          return data?.id ?? null;
        },
        { timeout: 60_000 },
      )
      .toBeTruthy();

    const row = await requireData(
      admin
        .from("contract_milestones")
        .select("id, status")
        .eq("contract_id", contractId)
        .ilike("name", `%${fx.runId}%`)
        .single(),
      "created milestone",
    );
    expect(row.status).toBe("planned");
    milestoneId = row.id;
  });

  test("04 — Finance marks milestone eligible", async ({ page }) => {
    expect(milestoneId, "milestoneId from step 03").toBeTruthy();
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/projects/${fx.projectId}/commercial/milestones`);
    await expectPageMarker(page, "project-milestones-page");
    await expect(page.getByTestId(`milestone-eligible-${milestoneId}`)).toBeVisible({ timeout: 20_000 });
    await page.getByTestId(`milestone-eligible-${milestoneId}`).click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("contract_milestones").select("status").eq("id", milestoneId).single(),
          "milestone eligible",
        );
        return row.status;
      })
      .toBe("eligible");
  });

  test("05 — Finance creates client valuation", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-valuations/new?projectId=${fx.projectId}`);
    await expectPageMarker(page, "valuation-create-page");

    await page.getByTestId("valuation-contract").selectOption({ value: contractId });
    const milestoneSelect = page.locator('select[name="milestoneId"]');
    if (await milestoneSelect.count()) {
      await milestoneSelect.selectOption({ value: milestoneId }).catch(() => undefined);
    }
    await page.getByTestId("valuation-gross").fill(String(GROSS_WORK));

    await Promise.all([
      page.waitForURL(/\/finance\/client-valuations\/?$/, { timeout: 60_000 }),
      page.getByTestId("valuation-submit").click(),
    ]);

    const admin = adminClient();
    const val = await requireData(
      admin
        .from("client_valuations")
        .select("id, status, total_claim")
        .eq("organization_id", fx.orgId)
        .eq("project_id", fx.projectId)
        .eq("contract_id", contractId)
        .order("created_at", { ascending: false })
        .limit(1)
        .single(),
      "created valuation",
    );
    expect(val.status).toBe("draft");
    expect(Number(val.total_claim)).toBeGreaterThan(CERTIFIED_AMOUNT);
    valuationId = val.id;
  });

  test("06 — Finance submits valuation for internal review", async ({ page }) => {
    expect(valuationId, "valuationId from step 05").toBeTruthy();
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-valuations/${valuationId}`);
    await expectPageMarker(page, "valuation-detail-page");
    await expect(page.getByTestId("valuation-approver")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("valuation-approver").selectOption({ value: fx.userIds.approver });
    await page.getByTestId("valuation-submit-button").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("client_valuations").select("status").eq("id", valuationId).single(),
          "valuation after submit",
        );
        return row.status;
      })
      .toBe("internal_review");
  });

  test("07 — Approver internally approves valuation", async ({ page }) => {
    await signInViaUI(page, fx.users.approver, fx.passwords.approver, "E2E approver");
    await page.goto(`/finance/client-valuations/${valuationId}`);
    await expectPageMarker(page, "valuation-detail-page");
    await expect(page.getByTestId("valuation-approve-internal-button")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("valuation-approve-internal-button").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("client_valuations").select("status").eq("id", valuationId).single(),
          "valuation after internal approve",
        );
        return row.status;
      })
      .toBe("submitted");
  });

  test("08 — Finance marks valuation under client review", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-valuations/${valuationId}`);
    await expectPageMarker(page, "valuation-detail-page");
    await expect(page.getByTestId("valuation-client-review-button")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("valuation-client-review-button").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("client_valuations").select("status").eq("id", valuationId).single(),
          "valuation client review",
        );
        return row.status;
      })
      .toBe("under_client_review");
  });

  test("09 — Finance records partial client certification", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-valuations/${valuationId}`);
    await expectPageMarker(page, "valuation-detail-page");
    await expect(page.getByTestId("cert-client-ref")).toBeVisible({ timeout: 20_000 });

    await page.getByTestId("cert-client-ref").fill(`CERT-E2E-${fx.runId}`);
    await page.getByTestId("cert-amount").fill(String(CERTIFIED_AMOUNT));
    await page.getByTestId("cert-date").fill(new Date().toISOString().slice(0, 10));
    await page.getByTestId("cert-submit").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin
            .from("client_valuations")
            .select("status, certified_amount, total_claim")
            .eq("id", valuationId)
            .single(),
          "valuation after certification",
        );
        return row.status;
      })
      .toBe("partially_certified");

    const val = await requireData(
      admin
        .from("client_valuations")
        .select("certified_amount, total_claim")
        .eq("id", valuationId)
        .single(),
      "certified amounts",
    );
    expect(Number(val.certified_amount)).toBe(CERTIFIED_AMOUNT);
    expect(Number(val.total_claim)).toBeGreaterThan(Number(val.certified_amount));
  });

  test("10 — Finance creates client invoice from valuation", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-invoices/new?valuationId=${valuationId}`);
    await expectPageMarker(page, "client-invoice-create-page");

    await page.getByTestId("invoice-valuation").selectOption({ value: valuationId });
    await page.getByTestId("client-invoice-number").fill(`CINV-E2E-${fx.runId}`);
    await page.getByTestId("client-invoice-date").fill(new Date().toISOString().slice(0, 10));
    await page.getByTestId("client-invoice-taxable").fill(String(CERTIFIED_AMOUNT));
    await page.locator('[name="vatRate"]').fill("0");

    await page.getByTestId("client-invoice-submit").click();

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const { data } = await admin
            .from("client_invoices")
            .select("id, status, total")
            .eq("organization_id", fx.orgId)
            .eq("invoice_number", `CINV-E2E-${fx.runId}`)
            .maybeSingle();
          return data?.id ?? null;
        },
        { timeout: 60_000 },
      )
      .toBeTruthy();

    const inv = await requireData(
      admin
        .from("client_invoices")
        .select("id, status, total")
        .eq("organization_id", fx.orgId)
        .eq("invoice_number", `CINV-E2E-${fx.runId}`)
        .single(),
      "client invoice",
    );
    expect(inv.status).toBe("draft");
    expect(Number(inv.total)).toBeLessThanOrEqual(CERTIFIED_AMOUNT + 0.01);
    invoiceId = inv.id;

    // Land on detail (warms route for issue step) whether redirect already happened or not.
    await page.goto(`/finance/client-invoices/${invoiceId}`);
    await expectPageMarker(page, "client-invoice-detail-page");
  });

  test("11 — Finance issues client invoice", async ({ page }) => {
    expect(invoiceId, "invoiceId from step 10").toBeTruthy();
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-invoices/${invoiceId}`);
    await expectPageMarker(page, "client-invoice-detail-page");
    await expect(page.getByTestId("client-invoice-issue-submit")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("client-invoice-issue-submit").click();

    // Issue redirects to the same path; wait for post-issue payment UI (not same-URL race).
    await expect(page.getByTestId("client-invoice-payment-card")).toBeVisible({ timeout: 60_000 });

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const row = await requireData(
            admin.from("client_invoices").select("status, issued_at").eq("id", invoiceId).single(),
            "issued client invoice",
          );
          return row.status;
        },
        { timeout: 60_000 },
      )
      .toBe("issued");
  });

  test("12 — Finance records partial client payment", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-invoices/${invoiceId}`);
    await expectPageMarker(page, "client-invoice-detail-page");
    await expect(page.getByTestId("client-payment-amount")).toBeVisible({ timeout: 20_000 });

    const admin = adminClient();
    const inv = await requireData(
      admin.from("client_invoices").select("total").eq("id", invoiceId).single(),
      "invoice total",
    );
    const halfAmount = (Number(inv.total) / 2).toFixed(2);

    await page.getByTestId("client-payment-amount").fill(halfAmount);
    await page.getByTestId("client-payment-reference").fill(`RCP-E2E-${fx.runId}-1`);
    await page.getByTestId("client-payment-submit").click();

    await expect
      .poll(
        async () => {
          const row = await requireData(
            admin.from("client_invoices").select("status").eq("id", invoiceId).single(),
            "partial payment status",
          );
          return row.status;
        },
        { timeout: 60_000 },
      )
      .toBe("partially_paid");
  });

  test("13 — Final payment — invoice PAID and outstanding 0", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/client-invoices/${invoiceId}`);
    await expectPageMarker(page, "client-invoice-detail-page");
    await expect(page.getByTestId("client-payment-amount")).toBeVisible({ timeout: 20_000 });

    const admin = adminClient();
    const inv = await requireData(
      admin.from("client_invoices").select("total").eq("id", invoiceId).single(),
      "invoice total final",
    );
    const payments = await requireData(
      admin.from("client_payments").select("amount").eq("client_invoice_id", invoiceId),
      "existing client payments",
    );
    const paid = payments.reduce((s: number, p: { amount: number | string }) => s + Number(p.amount), 0);
    const remaining = (Number(inv.total) - paid).toFixed(2);

    await page.getByTestId("client-payment-amount").fill(remaining);
    await page.getByTestId("client-payment-reference").fill(`RCP-E2E-${fx.runId}-2`);
    await page.getByTestId("client-payment-submit").click();

    await expect
      .poll(
        async () => {
          const row = await requireData(
            admin.from("client_invoices").select("status").eq("id", invoiceId).single(),
            "final client invoice",
          );
          return row.status;
        },
        { timeout: 60_000 },
      )
      .toBe("paid");

    const paidInv = await requireData(
      admin.from("client_invoices").select("total").eq("id", invoiceId).single(),
      "paid invoice total",
    );
    const allPays = await requireData(
      admin.from("client_payments").select("amount").eq("client_invoice_id", invoiceId),
      "all client payments",
    );
    const totalPaid = allPays.reduce((s: number, p: { amount: number | string }) => s + Number(p.amount), 0);
    const outstanding = Number(paidInv.total) - totalPaid;
    expect(Math.abs(outstanding)).toBeLessThan(0.01);
  });
});
