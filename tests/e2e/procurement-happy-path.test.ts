/**
 * Procurement Happy Path E2E
 *
 * Covers the full loop:
 * PR → Approval → RFQ → 2 Quotations → Comparison → Recommendation →
 * Award Approval → PO → PO Approval → Issue PO → Partial GRN → Final GRN →
 * Supplier Invoice → Match → Finance Approval → Partial Payment → Final Payment (PAID)
 *
 * Requires:
 *  - NEXT_PUBLIC_SUPABASE_URL
 *  - NEXT_PUBLIC_SUPABASE_ANON_KEY
 *  - SUPABASE_SERVICE_ROLE_KEY
 *  - E2E_BASE_URL (default: http://localhost:3000)
 *  - LIVE_TEST_ENABLED=true
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

test.describe("Procurement Happy Path", () => {
  test.describe.configure({ mode: "serial", retries: 0 });
  test.skip(!ENABLED, "LIVE_TEST_ENABLED not set");

  let fx: E2EFixture;
  let prId: string;
  let rfqId: string;
  let quote1Id: string;
  let poId: string;
  let invoiceId: string;

  test.beforeAll(async () => {
    const runId = crypto.randomUUID().slice(0, 8);
    fx = await createE2EFixture(runId);
  });

  test.afterAll(async () => {
    await cleanupE2EFixture(fx ?? null);
  });

  test("01 — Engineer creates PR", async ({ page }) => {
    await signInViaUI(page, fx.users.engineer, fx.passwords.engineer, "E2E engineer");
    await page.goto("/procurement/purchase-requests/new");
    await expectPageMarker(page, "pr-create-page");
    await assertAuthenticatedPage(page, "E2E engineer");

    await page.getByTestId("pr-project-id").selectOption({ value: fx.projectId });
    await page.getByTestId("pr-justification").fill(`E2E طلب شراء اختباري ${fx.runId}`);
    await page.getByTestId("pr-item-description").fill(`جهاز اختبار ${fx.runId}`);
    await page.getByTestId("pr-quantity").fill("10");
    await page.getByTestId("pr-unit-cost").fill("500");

    await Promise.all([
      page.waitForURL(/\/procurement\/purchase-requests\/?$/, { timeout: 60_000 }),
      page.getByTestId("pr-create-submit").click(),
    ]);

    const admin = adminClient();
    const pr = await requireData(
      admin
        .from("purchase_requests")
        .select("id, status, project_id")
        .eq("organization_id", fx.orgId)
        .eq("project_id", fx.projectId)
        .ilike("justification", `%${fx.runId}%`)
        .single(),
      "created purchase request",
    );
    expect(pr.status).toBe("draft");
    expect(pr.project_id).toBe(fx.projectId);
    prId = pr.id;
  });

  test("02 — PR submitted for approval", async ({ page }) => {
    expect(prId, "prId from step 01").toBeTruthy();
    await signInViaUI(page, fx.users.engineer, fx.passwords.engineer, "E2E engineer");
    await page.goto(`/procurement/purchase-requests/${prId}`);
    await expectPageMarker(page, "pr-detail-page");
    await expect(page.getByTestId("pr-approver")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("pr-approver").selectOption({ value: fx.userIds.approver });
    await page.getByTestId("pr-submit-approval").click();

    const admin = adminClient();
    await expect
      .poll(async () => {
        const pr = await requireData(
          admin.from("purchase_requests").select("status").eq("id", prId).single(),
          "PR after submit",
        );
        return pr.status;
      })
      .toBe("under_review");
  });

  test("03 — Approver approves PR", async ({ page }) => {
    await signInViaUI(page, fx.users.approver, fx.passwords.approver, "E2E approver");
    const admin = adminClient();
    const pr = await requireData(
      admin.from("purchase_requests").select("approval_request_id").eq("id", prId).single(),
      "PR approval_request_id",
    );
    expect(pr.approval_request_id).toBeTruthy();
    const step = await requireData(
      admin.from("approval_steps").select("id").eq("request_id", pr.approval_request_id!).single(),
      "PR approval step",
    );

    await page.goto("/approvals");
    const form = page
      .locator("form")
      .filter({ has: page.locator(`input[name="stepId"][value="${step.id}"]`) })
      .first();
    await expect(form.locator('select[name="officialCode"]')).toBeVisible({ timeout: 20_000 });
    await form.locator('select[name="officialCode"]').selectOption("A");
    await form.locator('[type="submit"]').first().click();
    await expect
      .poll(async () => {
        const row = await requireData(
          admin.from("purchase_requests").select("status").eq("id", prId).single(),
          "PR status poll",
        );
        return row.status;
      })
      .toBe("approved");
  });

  test("04 — Create RFQ from approved PR", async ({ page }) => {
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    await page.goto(`/procurement/purchase-requests/${prId}`);
    await expect(page.locator('[name="responseDueDate"]')).toBeVisible({ timeout: 20_000 });
    const future = new Date();
    future.setDate(future.getDate() + 14);
    await page.fill('[name="responseDueDate"]', future.toISOString().slice(0, 10));
    await page.locator('form').filter({ has: page.locator('[name="responseDueDate"]') }).locator('button[type="submit"]').click();

    const admin = adminClient();
    await expect.poll(async () => {
      const { data } = await admin
        .from("rfqs")
        .select("id, status")
        .eq("organization_id", fx.orgId)
        .eq("purchase_request_id", prId)
        .maybeSingle();
      return data?.status ?? null;
    }).toBe("draft");

    const rfq = await requireData(
      admin
        .from("rfqs")
        .select("id, status")
        .eq("organization_id", fx.orgId)
        .eq("purchase_request_id", prId)
        .single(),
      "RFQ from PR",
    );
    rfqId = rfq.id;
  });

  test("05 — Add suppliers and issue RFQ", async ({ page }) => {
    expect(rfqId, "rfqId from step 04").toBeTruthy();
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    const admin = adminClient();

    await requireData(
      admin
        .from("rfq_suppliers")
        .insert([
          {
            organization_id: fx.orgId,
            rfq_id: rfqId,
            supplier_id: fx.supplierIds.alpha,
            sent_by: fx.userIds.procurement,
          },
          {
            organization_id: fx.orgId,
            rfq_id: rfqId,
            supplier_id: fx.supplierIds.beta,
            sent_by: fx.userIds.procurement,
          },
        ])
        .select("id"),
      "rfq_suppliers invite",
    );

    await page.goto(`/procurement/rfqs/${rfqId}`);
    const issueBtn = page.locator("form").filter({ has: page.locator('input[name="rfqId"]') }).locator('button[type="submit"]');
    await expect(issueBtn).toBeVisible({ timeout: 20_000 });
    await issueBtn.click();

    await expect.poll(async () => {
      const row = await requireData(admin.from("rfqs").select("status").eq("id", rfqId).single(), "RFQ status");
      return row.status;
    }).toBe("issued");
  });

  test("06 — Register two quotations", async ({ page }) => {
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    const admin = adminClient();
    const rfqItems = await requireData(
      admin.from("rfq_items").select("id").eq("rfq_id", rfqId),
      "rfq_items",
    );
    const itemId = rfqItems[0]?.id;
    expect(itemId, "RFQ must have at least one item").toBeTruthy();

    await page.goto(`/procurement/rfqs/${rfqId}/quotations/new`);
    await expectPageMarker(page, "quotation-create-page");
    await page.getByTestId("quotation-supplier").selectOption({ value: fx.supplierIds.alpha });
    await page.getByTestId("quotation-number").fill(`QT-E2E-${fx.runId}-A`);
    await page.fill(`[name="price_${itemId}"]`, "450");
    await Promise.all([
      page.waitForURL(new RegExp(`/procurement/rfqs/${rfqId}/?$`), { timeout: 60_000 }),
      page.getByTestId("quotation-submit").click(),
    ]);

    const q1 = await requireData(
      admin
        .from("supplier_quotations")
        .select("id")
        .eq("rfq_id", rfqId)
        .eq("supplier_id", fx.supplierIds.alpha)
        .single(),
      "quotation 1",
    );
    quote1Id = q1.id;

    await page.goto(`/procurement/rfqs/${rfqId}/quotations/new`);
    await expectPageMarker(page, "quotation-create-page");
    await page.getByTestId("quotation-supplier").selectOption({ value: fx.supplierIds.beta });
    await page.getByTestId("quotation-number").fill(`QT-E2E-${fx.runId}-B`);
    await page.fill(`[name="price_${itemId}"]`, "480");
    await Promise.all([
      page.waitForURL(new RegExp(`/procurement/rfqs/${rfqId}/?$`), { timeout: 60_000 }),
      page.getByTestId("quotation-submit").click(),
    ]);

    await requireData(
      admin
        .from("supplier_quotations")
        .select("id")
        .eq("rfq_id", rfqId)
        .eq("supplier_id", fx.supplierIds.beta)
        .single(),
      "quotation 2",
    );
    const { count } = await admin
      .from("supplier_quotations")
      .select("id", { count: "exact", head: true })
      .eq("rfq_id", rfqId);
    expect(count).toBe(2);
  });

  test("07 — Open comparison matrix and recommend supplier", async ({ page }) => {
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    await page.goto(`/procurement/rfqs/${rfqId}/comparison`);
    await expectPageMarker(page, "comparison-page");
    await expect(page.getByTestId("award-recommend-form")).toBeVisible({ timeout: 20_000 });

    await page.getByTestId("award-quotation").selectOption({ value: quote1Id });
    await page.getByTestId("award-supplier").selectOption({ value: fx.supplierIds.alpha });
    await page
      .getByTestId("award-reason")
      .fill(`المورد ألفا يقدم أفضل سعر ويلتزم بالمواصفات لهذا الاختبار ${fx.runId}`);
    await page.getByTestId("award-approver").selectOption({ value: fx.userIds.approver });
    await page.getByTestId("award-submit").click();

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const { data } = await admin
            .from("quotation_comparisons")
            .select("status, recommended_quotation_id")
            .eq("rfq_id", rfqId)
            .maybeSingle();
          return data?.status ?? null;
        },
        { timeout: 60_000 },
      )
      .toBe("pending_approval");

    const comp = await requireData(
      admin.from("quotation_comparisons").select("status, recommended_quotation_id").eq("rfq_id", rfqId).single(),
      "comparison",
    );
    expect(comp.recommended_quotation_id).toBe(quote1Id);
  });

  test("08 — Approver awards the recommendation", async ({ page }) => {
    await signInViaUI(page, fx.users.approver, fx.passwords.approver, "E2E approver");
    const admin = adminClient();
    const comp = await requireData(
      admin.from("quotation_comparisons").select("id, approval_request_id").eq("rfq_id", rfqId).single(),
      "comparison for award",
    );
    const step = await requireData(
      admin.from("approval_steps").select("id").eq("request_id", comp.approval_request_id!).single(),
      "award approval step",
    );

    await page.goto("/approvals");
    const form = page
      .locator("form")
      .filter({ has: page.locator(`input[name="stepId"][value="${step.id}"]`) })
      .first();
    await expect(form.locator('select[name="officialCode"]')).toBeVisible({ timeout: 20_000 });
    await form.locator('select[name="officialCode"]').selectOption("A");
    await form.locator('[type="submit"]').first().click();

    await expect.poll(async () => {
      const row = await requireData(
        admin.from("quotation_comparisons").select("status").eq("id", comp.id).single(),
        "award status",
      );
      return row.status;
    }).toBe("awarded");
  });

  test("09 — Create PO from awarded quotation", async ({ page }) => {
    const admin = adminClient();
    const award = await requireData(
      admin
        .from("quotation_comparisons")
        .select("status, recommended_quotation_id")
        .eq("rfq_id", rfqId)
        .single(),
      "award state before PO",
    );
    expect(award.status).toBe("awarded");
    expect(award.recommended_quotation_id).toBe(quote1Id);

    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    await page.goto(`/procurement/purchase-orders/new?quotationId=${quote1Id}`);
    await expectPageMarker(page, "po-create-page");
    const future = new Date();
    future.setDate(future.getDate() + 30);
    await page.getByTestId("po-delivery-date").fill(future.toISOString().slice(0, 10));
    await Promise.all([
      page.waitForURL(/\/procurement\/purchase-orders\/?$/, { timeout: 60_000 }),
      page.getByTestId("po-create-submit").click(),
    ]);

    await expect
      .poll(
        async () => {
          const { data } = await admin
            .from("purchase_orders")
            .select("id, status")
            .eq("quotation_id", quote1Id)
            .maybeSingle();
          return data?.status ?? null;
        },
        { timeout: 60_000 },
      )
      .toBe("draft");

    const po = await requireData(
      admin.from("purchase_orders").select("id, status").eq("quotation_id", quote1Id).single(),
      "purchase order",
    );
    poId = po.id;
  });

  test("10 — Submit PO for approval", async ({ page }) => {
    expect(poId, "poId from step 09").toBeTruthy();
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    await page.goto(`/procurement/purchase-orders/${poId}`);
    await expect(page.locator('select[name="approverProfileId"]')).toBeVisible({ timeout: 20_000 });
    await page.selectOption('select[name="approverProfileId"]', { value: fx.userIds.approver });
    await page.locator('form').filter({ has: page.locator('select[name="approverProfileId"]') }).locator('[type="submit"]').click();

    const admin = adminClient();
    await expect.poll(async () => {
      const row = await requireData(admin.from("purchase_orders").select("status").eq("id", poId).single(), "PO status");
      return row.status;
    }).toBe("pending_approval");
  });

  test("11 — Approver approves PO", async ({ page }) => {
    await signInViaUI(page, fx.users.approver, fx.passwords.approver, "E2E approver");
    const admin = adminClient();
    const po = await requireData(
      admin.from("purchase_orders").select("approval_request_id").eq("id", poId).single(),
      "PO approval_request_id",
    );
    const step = await requireData(
      admin.from("approval_steps").select("id").eq("request_id", po.approval_request_id!).single(),
      "PO approval step",
    );

    await page.goto("/approvals");
    const form = page
      .locator("form")
      .filter({ has: page.locator(`input[name="stepId"][value="${step.id}"]`) })
      .first();
    await expect(form.locator('select[name="officialCode"]')).toBeVisible({ timeout: 20_000 });
    await form.locator('select[name="officialCode"]').selectOption("A");
    await form.locator('[type="submit"]').first().click();

    await expect.poll(async () => {
      const row = await requireData(admin.from("purchase_orders").select("status").eq("id", poId).single(), "PO approved");
      return row.status;
    }).toBe("approved");
  });

  test("12 — Issue PO", async ({ page }) => {
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    await page.goto(`/procurement/purchase-orders/${poId}`);
    await expect(page.getByTestId("po-issue-submit")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("po-issue-submit").click();

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const row = await requireData(
            admin.from("purchase_orders").select("status, issued_at").eq("id", poId).single(),
            "issued PO",
          );
          return row.status;
        },
        { timeout: 60_000 },
      )
      .toBe("issued");
    const po = await requireData(
      admin.from("purchase_orders").select("issued_at").eq("id", poId).single(),
      "issued_at",
    );
    expect(po.issued_at).toBeTruthy();
  });

  test("13 — Assert issued PO commercial fields are immutable", async () => {
    // Must use authenticated app JWT — service_role bypasses the immutability trigger by design.
    const procurement = await signInApiClient(fx.users.procurement, fx.passwords.procurement);
    const po = await requireData(
      procurement.from("purchase_orders").select("total, currency").eq("id", poId).single(),
      "PO before immutability check",
    );
    const { error } = await procurement.from("purchase_orders").update({ total: 999999.99 }).eq("id", poId);
    expect(error).toBeTruthy();
    expect(error!.message).toMatch(/immutable/i);

    const unchanged = await requireData(
      procurement.from("purchase_orders").select("total").eq("id", poId).single(),
      "PO total after blocked update",
    );
    expect(Number(unchanged.total)).toBe(Number(po.total));
  });

  test("14 — Post PARTIAL goods receipt", async ({ page }) => {
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    await page.goto(`/procurement/goods-receipts/new?poId=${poId}`);
    await expectPageMarker(page, "grn-create-page");

    const admin = adminClient();
    const items = await requireData(
      admin.from("purchase_order_items").select("id, quantity").eq("purchase_order_id", poId),
      "PO items for partial GRN",
    );
    const item = items[0];
    expect(item).toBeTruthy();
    const partialQty = Math.floor(Number(item.quantity) / 2) || 1;
    await page.fill(`[name="received_${item.id}"]`, String(partialQty));
    await page.fill(`[name="accepted_${item.id}"]`, String(partialQty));
    await Promise.all([
      page.waitForURL(/\/procurement\/goods-receipts\/?$/, { timeout: 60_000 }),
      page.getByTestId("grn-submit").click(),
    ]);

    await expect
      .poll(
        async () => {
          const { count } = await admin
            .from("goods_receipts")
            .select("id", { count: "exact", head: true })
            .eq("purchase_order_id", poId);
          return count ?? 0;
        },
        { timeout: 60_000 },
      )
      .toBeGreaterThan(0);
  });

  test("15 — Post FINAL goods receipt", async ({ page }) => {
    await signInViaUI(page, fx.users.procurement, fx.passwords.procurement, "E2E procurement");
    await page.goto(`/procurement/goods-receipts/new?poId=${poId}`);
    await expectPageMarker(page, "grn-create-page");

    const admin = adminClient();
    const items = await requireData(
      admin
        .from("purchase_order_items")
        .select("id, quantity, received_quantity")
        .eq("purchase_order_id", poId),
      "PO items for final GRN",
    );
    const item = items[0];
    const remaining = Math.max(0, Number(item.quantity) - Number(item.received_quantity ?? 0));
    if (remaining > 0) {
      await page.fill(`[name="received_${item.id}"]`, String(remaining));
      await page.fill(`[name="accepted_${item.id}"]`, String(remaining));
      await Promise.all([
        page.waitForURL(/\/procurement\/goods-receipts\/?$/, { timeout: 60_000 }),
        page.getByTestId("grn-submit").click(),
      ]);
    }

    await expect
      .poll(
        async () => {
          const { count } = await admin
            .from("goods_receipts")
            .select("id", { count: "exact", head: true })
            .eq("purchase_order_id", poId);
          return count ?? 0;
        },
        { timeout: 60_000 },
      )
      .toBeGreaterThanOrEqual(2);
  });

  test("16 — Finance creates supplier invoice", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto("/finance/supplier-invoices/new");
    await expectPageMarker(page, "invoice-create-page");

    const admin = adminClient();
    const po = await requireData(
      admin.from("purchase_orders").select("project_id, supplier_id, total").eq("id", poId).single(),
      "PO for invoice",
    );

    await page.getByTestId("invoice-project").selectOption({ value: po.project_id });
    await page.getByTestId("invoice-supplier").selectOption({ value: po.supplier_id });
    await page.getByTestId("invoice-po").selectOption({ value: poId });
    await page.getByTestId("invoice-number").fill(`INV-E2E-${fx.runId}`);
    await page.getByTestId("invoice-date").fill(new Date().toISOString().slice(0, 10));
    await page.getByTestId("invoice-subtotal").fill(String(Number(po.total) / 1.15));
    await Promise.all([
      page.waitForURL(/\/finance\/supplier-invoices\/?$/, { timeout: 60_000 }),
      page.getByTestId("invoice-submit").click(),
    ]);

    await expect
      .poll(
        async () => {
          const { data } = await admin
            .from("supplier_invoices")
            .select("id, status")
            .eq("organization_id", fx.orgId)
            .eq("invoice_number", `INV-E2E-${fx.runId}`)
            .maybeSingle();
          return data?.id ?? null;
        },
        { timeout: 60_000 },
      )
      .toBeTruthy();

    const inv = await requireData(
      admin
        .from("supplier_invoices")
        .select("id, status")
        .eq("organization_id", fx.orgId)
        .eq("invoice_number", `INV-E2E-${fx.runId}`)
        .single(),
      "supplier invoice",
    );
    invoiceId = inv.id;
    expect(["received", "matched", "discrepancy", "under_review"]).toContain(inv.status);
  });

  test("17 — Finance approves invoice for payment", async ({ page }) => {
    expect(invoiceId, "invoiceId from step 16").toBeTruthy();
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/supplier-invoices/${invoiceId}`);
    await expectPageMarker(page, "invoice-detail-page");
    await expect(page.getByTestId("invoice-approve-submit")).toBeVisible({ timeout: 20_000 });
    await page.getByTestId("invoice-approve-submit").click();

    const admin = adminClient();
    await expect
      .poll(
        async () => {
          const row = await requireData(
            admin.from("supplier_invoices").select("status").eq("id", invoiceId).single(),
            "invoice approve status",
          );
          return row.status;
        },
        { timeout: 60_000 },
      )
      .toBe("approved_for_payment");
  });

  test("18 — Finance records partial payment", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/supplier-invoices/${invoiceId}`);
    await expectPageMarker(page, "invoice-detail-page");
    await expect(page.getByTestId("payment-amount")).toBeVisible({ timeout: 20_000 });

    const admin = adminClient();
    const inv = await requireData(
      admin.from("supplier_invoices").select("total").eq("id", invoiceId).single(),
      "invoice total",
    );
    const halfAmount = (Number(inv.total) / 2).toFixed(2);

    await page.getByTestId("payment-amount").fill(halfAmount);
    await page.getByTestId("payment-reference").fill(`PAY-E2E-${fx.runId}-1`);
    await page.getByTestId("payment-submit").click();

    await expect
      .poll(
        async () => {
          const row = await requireData(
            admin.from("supplier_invoices").select("status").eq("id", invoiceId).single(),
            "partial payment status",
          );
          return row.status;
        },
        { timeout: 60_000 },
      )
      .toBe("partially_paid");
  });

  test("19 — Finance records final payment — invoice becomes PAID", async ({ page }) => {
    await signInViaUI(page, fx.users.finance, fx.passwords.finance, "E2E finance");
    await page.goto(`/finance/supplier-invoices/${invoiceId}`);
    await expectPageMarker(page, "invoice-detail-page");
    await expect(page.getByTestId("payment-amount")).toBeVisible({ timeout: 20_000 });

    const admin = adminClient();
    const inv = await requireData(
      admin.from("supplier_invoices").select("total").eq("id", invoiceId).single(),
      "invoice total final",
    );
    const payments = await requireData(
      admin.from("supplier_payments").select("amount").eq("supplier_invoice_id", invoiceId),
      "existing payments",
    );
    const paid = payments.reduce((s: number, p: { amount: number | string }) => s + Number(p.amount), 0);
    const remaining = (Number(inv.total) - paid).toFixed(2);

    await page.getByTestId("payment-amount").fill(remaining);
    await page.getByTestId("payment-reference").fill(`PAY-E2E-${fx.runId}-2`);
    await page.getByTestId("payment-submit").click();

    await expect
      .poll(
        async () => {
          const row = await requireData(
            admin.from("supplier_invoices").select("status").eq("id", invoiceId).single(),
            "final payment status",
          );
          return row.status;
        },
        { timeout: 60_000 },
      )
      .toBe("paid");
  });

  test("20 — ASSERT full procurement state", async () => {
    const admin = adminClient();

    const pr = await requireData(admin.from("purchase_requests").select("status").eq("id", prId).single(), "final PR");
    expect(["approved", "converted_to_rfq"]).toContain(pr.status);

    const rfq = await requireData(admin.from("rfqs").select("status").eq("id", rfqId).single(), "final RFQ");
    expect(rfq.status).toBe("awarded");

    const { count: qtCount } = await admin
      .from("supplier_quotations")
      .select("id", { count: "exact", head: true })
      .eq("rfq_id", rfqId);
    expect(qtCount).toBe(2);

    const comp = await requireData(
      admin.from("quotation_comparisons").select("status, recommendation_reason").eq("rfq_id", rfqId).single(),
      "final comparison",
    );
    expect(comp.status).toBe("awarded");
    expect(comp.recommendation_reason?.length).toBeGreaterThan(5);

    const po = await requireData(
      admin.from("purchase_orders").select("status, issued_at").eq("id", poId).single(),
      "final PO",
    );
    expect(["issued", "partially_delivered", "delivered", "partially_invoiced", "invoiced"]).toContain(po.status);
    expect(po.issued_at).toBeTruthy();

    const { count: grnCount } = await admin
      .from("goods_receipts")
      .select("id", { count: "exact", head: true })
      .eq("purchase_order_id", poId);
    expect(grnCount).toBeGreaterThanOrEqual(2);

    const inv = await requireData(
      admin.from("supplier_invoices").select("status, total").eq("id", invoiceId).single(),
      "final invoice",
    );
    expect(inv.status).toBe("paid");

    const allPayments = await requireData(
      admin.from("supplier_payments").select("amount").eq("supplier_invoice_id", invoiceId),
      "final payments",
    );
    const totalPaid = allPayments.reduce((s: number, p: { amount: number | string }) => s + Number(p.amount), 0);
    expect(Math.abs(totalPaid - Number(inv.total))).toBeLessThan(0.01);
  });
});
