import "../setup-env";
import { describe, expect, it, beforeAll, afterAll } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  adminClient,
  liveTestConfigured,
  provisionLiveFixture,
  signInAs,
  type LiveFixture,
} from "./helpers";

const configured = liveTestConfigured();

describe.skipIf(!configured)("live Phase 3 commercial & procurement", () => {
  let fx: LiveFixture;
  let phase3Ready = false;
  let supplierId: string;
  let poId: string;
  let poItemId: string;
  let draftPoId: string;
  let invoiceId: string;
  let paymentFlowInvoiceId: string;
  let concurrentInvoiceId: string;
  let pmClient: SupabaseClient;
  let adminAuthedClient: SupabaseClient;
  let engineerClient: SupabaseClient;
  let financeClient: SupabaseClient;
  let restrictedClient: SupabaseClient;

  beforeAll(async () => {
    fx = await provisionLiveFixture();
    const admin = adminClient();
    const { error } = await admin.from("suppliers").select("id").limit(1);
    phase3Ready = !error;
    if (!phase3Ready) {
      console.warn("[live-test] Phase 3 tables missing — apply migrations 031–045 then re-run.");
      return;
    }

    await admin.from("project_members").upsert(
      {
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        profile_id: fx.users.engineer.id,
        role_label: "engineer",
        is_active: true,
      },
      { onConflict: "project_id,profile_id" },
    );

    const { data: code } = await admin.rpc("generate_supplier_code", {
      p_organization_id: fx.orgAId,
    });
    const { data: supplier } = await admin
      .from("suppliers")
      .insert({
        organization_id: fx.orgAId,
        supplier_code: code ?? `SUP-T-${fx.runId}`,
        legal_name: `Supplier ${fx.runId}`,
        iban: "SA0380000000608010167519",
        bank_name: "Test Bank",
        status: "active",
        created_by: fx.users.admin.id,
      })
      .select("id")
      .single();
    supplierId = supplier!.id;

    pmClient = await signInAs(fx.users.pm.email, fx.users.pm.password);
    adminAuthedClient = await signInAs(fx.users.admin.email, fx.users.admin.password);
    engineerClient = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    financeClient = await signInAs(fx.users.finance.email, fx.users.finance.password);
    restrictedClient = await signInAs(fx.users.restricted.email, fx.users.restricted.password);

    const pm = pmClient;

    const { data: draftNum } = await pm.rpc("generate_commercial_number", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_doc_type: "PO",
    });
    const { data: draftPo } = await admin
      .from("purchase_orders")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        supplier_id: supplierId,
        po_number: `${draftNum ?? `MT-D-${fx.runId}`}-D`,
        currency: "SAR",
        subtotal: 500,
        vat_amount: 75,
        total: 575,
        status: "draft",
        created_by: fx.users.pm.id,
      })
      .select("id")
      .single();
    draftPoId = draftPo!.id;

    const { data: prNum } = await pm.rpc("generate_commercial_number", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_doc_type: "PO",
    });
    const { data: po } = await admin
      .from("purchase_orders")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        supplier_id: supplierId,
        po_number: prNum ?? `MT-PO-${fx.runId}`,
        currency: "SAR",
        subtotal: 1000,
        vat_amount: 150,
        total: 1150,
        status: "approved",
        created_by: fx.users.pm.id,
      })
      .select("id")
      .single();
    poId = po!.id;

    const { data: poItem } = await admin
      .from("purchase_order_items")
      .insert({
        organization_id: fx.orgAId,
        purchase_order_id: poId,
        line_no: 1,
        description: "Test item",
        quantity: 10,
        unit: "EA",
        unit_price: 100,
        vat_amount: 150,
        line_total: 1150,
      })
      .select("id")
      .single();
    poItemId = poItem!.id;

    const { error: issueErr } = await pm.rpc("issue_purchase_order", { p_po_id: poId });
    expect(issueErr).toBeNull();

    const { data: inv } = await admin
      .from("supplier_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        supplier_id: supplierId,
        purchase_order_id: poId,
        invoice_number: `INV-${fx.runId}`,
        invoice_date: new Date().toISOString().slice(0, 10),
        due_date: new Date().toISOString().slice(0, 10),
        currency: "SAR",
        subtotal: 1000,
        vat_amount: 150,
        total: 1150,
        status: "approved_for_payment",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    invoiceId = inv!.id;

    const { data: payInv } = await admin
      .from("supplier_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        supplier_id: supplierId,
        invoice_number: `INV-PAY-${fx.runId}`,
        invoice_date: new Date().toISOString().slice(0, 10),
        currency: "SAR",
        subtotal: 1000,
        vat_amount: 150,
        total: 1000,
        status: "approved_for_payment",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    paymentFlowInvoiceId = payInv!.id;

    const { data: concInv } = await admin
      .from("supplier_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        supplier_id: supplierId,
        invoice_number: `INV-CONC-${fx.runId}`,
        invoice_date: new Date().toISOString().slice(0, 10),
        currency: "SAR",
        subtotal: 1000,
        total: 1000,
        status: "approved_for_payment",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    concurrentInvoiceId = concInv!.id;
  }, 120_000);

  afterAll(async () => {
    if (fx) await fx.cleanup();
  }, 60_000);

  async function createApprovalRequestFixture(input: {
    entityType: string;
    entityId: string;
    approverId: string;
    title: string;
    sequence?: number;
    status?: "pending" | "in_progress";
  }) {
    const admin = adminClient();
    const dueAt = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();
    const { data: request, error: requestError } = await admin
      .from("approval_requests")
      .insert({
        organization_id: fx.orgAId,
        entity_type: input.entityType,
        entity_id: input.entityId,
        title: input.title,
        status: "in_progress",
        mode: "sequential",
        requested_by: fx.users.admin.id,
        due_at: dueAt,
        warning_at: new Date(Date.parse(dueAt) - 24 * 60 * 60 * 1000).toISOString(),
      })
      .select("id")
      .single<{ id: string }>();
    expect(requestError).toBeNull();

    const { data: step, error: stepError } = await admin
      .from("approval_steps")
      .insert({
        organization_id: fx.orgAId,
        request_id: request!.id,
        sequence: input.sequence ?? 1,
        approver_type: "user",
        user_id: input.approverId,
        status: input.status ?? "in_progress",
        due_at: dueAt,
      })
      .select("id")
      .single<{ id: string }>();
    expect(stepError).toBeNull();

    return { requestId: request!.id, stepId: step!.id };
  }

  it("schema has Phase 3 commercial RPCs", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { error } = await admin.rpc("generate_supplier_code", {
      p_organization_id: fx.orgAId,
    });
    expect(error?.message ?? "").not.toMatch(/Could not find the function/i);
  });

  it("cross-org supplier isolation", async () => {
    if (!phase3Ready || !supplierId) return;
    const admin = adminClient();
    const { data: orgBSup } = await admin
      .from("suppliers")
      .insert({
        organization_id: fx.orgBId,
        supplier_code: `SUP-B-${fx.runId}`,
        legal_name: "Org B Supplier",
        status: "active",
        created_by: fx.users.admin.id,
      })
      .select("id")
      .single();

    const pm = pmClient;
    const { data, error } = await pm.from("suppliers").select("id").eq("id", orgBSup!.id);
    expect(error).toBeNull();
    expect(data ?? []).toHaveLength(0);
  });

  it("engineer cannot read supplier banking via RPC", async () => {
    if (!phase3Ready || !supplierId) return;
    const engineer = engineerClient;
    const { error } = await engineer.rpc("get_supplier_banking", { p_supplier_id: supplierId });
    expect(error?.message ?? "").toMatch(/FORBIDDEN/i);
  });

  it("finance can read supplier banking via RPC", async () => {
    if (!phase3Ready || !supplierId) return;
    const finance = financeClient;
    const { data, error } = await finance.rpc("get_supplier_banking", {
      p_supplier_id: supplierId,
    });
    expect(error).toBeNull();
    expect(data?.[0]?.iban).toBeTruthy();
  });

  it("engineer can create PR on assigned project", async () => {
    if (!phase3Ready) return;
    const engineer = engineerClient;
    const { data: num, error: numErr } = await engineer.rpc("generate_commercial_number", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_doc_type: "PR",
    });
    expect(numErr).toBeNull();
    expect(num).toBeTruthy();

    const { error } = await engineer.from("purchase_requests").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      pr_number: num!,
      requested_by: fx.users.engineer.id,
      justification: "Live test PR",
      status: "draft",
      created_by: fx.users.engineer.id,
    });
    expect(error).toBeNull();
  });

  it("unauthorized user denied PR on project", async () => {
    if (!phase3Ready) return;
    const restricted = restrictedClient;
    const { error } = await restricted.from("purchase_requests").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      pr_number: `MT-BLOCK-${fx.runId}`,
      requested_by: fx.users.restricted.id,
      justification: "Should fail",
      status: "draft",
      created_by: fx.users.restricted.id,
    });
    expect(error).not.toBeNull();
  });

  it("concurrent commercial numbering is unique", async () => {
    if (!phase3Ready) return;
    const pm = pmClient;
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        pm.rpc("generate_commercial_number", {
          p_organization_id: fx.orgAId,
          p_project_id: fx.projectId,
          p_doc_type: "PR",
        }),
      ),
    );
    const numbers = results.map((r) => r.data).filter(Boolean) as string[];
    expect(new Set(numbers).size).toBe(numbers.length);
  });

  it("draft PO authorized edit succeeds", async () => {
    if (!phase3Ready || !draftPoId) return;
    const pm = pmClient;
    const { error } = await pm.from("purchase_orders").update({ total: 600 }).eq("id", draftPoId);
    expect(error).toBeNull();
  });

  it("issued PO is immutable", async () => {
    if (!phase3Ready || !poId) return;
    const pm = pmClient;
    const { error } = await pm
      .from("purchase_orders")
      .update({ total: 9999 })
      .eq("id", poId);
    expect(error?.message ?? "").toMatch(/immutable/i);
  });

  it("issued PO item UPDATE fails", async () => {
    if (!phase3Ready || !poItemId) return;
    const pm = pmClient;
    const { error } = await pm
      .from("purchase_order_items")
      .update({ quantity: 99 })
      .eq("id", poItemId);
    expect(error?.message ?? "").toMatch(/immutable/i);
  });

  it("issued PO item DELETE fails", async () => {
    if (!phase3Ready || !poItemId) return;
    const pm = pmClient;
    const { error } = await pm.from("purchase_order_items").delete().eq("id", poItemId);
    expect(error?.message ?? "").toMatch(/immutable/i);
  });

  it("issued PO item INSERT fails", async () => {
    if (!phase3Ready || !poId) return;
    const pm = pmClient;
    const { error } = await pm.from("purchase_order_items").insert({
      organization_id: fx.orgAId,
      purchase_order_id: poId,
      line_no: 2,
      description: "Late line",
      quantity: 1,
      unit_price: 10,
      line_total: 10,
    });
    expect(error?.message ?? "").toMatch(/immutable/i);
  });

  it("unauthorized user cannot issue PO", async () => {
    if (!phase3Ready || !draftPoId) return;
    const engineer = engineerClient;
    const { error } = await engineer.rpc("issue_purchase_order", { p_po_id: draftPoId });
    expect(error?.message ?? "").toMatch(/FORBIDDEN/i);
  });

  it("issued PO values unchanged after attempted mutation", async () => {
    if (!phase3Ready || !poId) return;
    const admin = adminClient();
    const { data } = await admin.from("purchase_orders").select("total").eq("id", poId).single();
    expect(Number(data?.total)).toBe(1150);
  });

  it("duplicate supplier invoice blocked", async () => {
    if (!phase3Ready || !supplierId) return;
    const admin = adminClient();
    const { error } = await admin.from("supplier_invoices").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      supplier_id: supplierId,
      invoice_number: `INV-${fx.runId}`,
      invoice_date: new Date().toISOString().slice(0, 10),
      currency: "SAR",
      subtotal: 100,
      vat_amount: 15,
      total: 115,
      status: "received",
      created_by: fx.users.finance.id,
    });
    expect(error).not.toBeNull();
  });

  it("finance can record valid partial payment", async () => {
    if (!phase3Ready || !paymentFlowInvoiceId) return;
    const finance = financeClient;
    const { data, error } = await finance.rpc("record_supplier_payment", {
      p_invoice_id: paymentFlowInvoiceId,
      p_amount: 400,
      p_payment_date: new Date().toISOString().slice(0, 10),
      p_payment_reference: `PAY-P1-${fx.runId}`,
    });
    expect(error).toBeNull();
    expect(data?.amount).toBe(400);
  });

  it("engineer cannot record supplier payment", async () => {
    if (!phase3Ready || !invoiceId) return;
    const engineer = engineerClient;
    const { error } = await engineer.rpc("record_supplier_payment", {
      p_invoice_id: invoiceId,
      p_amount: 100,
      p_payment_date: new Date().toISOString().slice(0, 10),
      p_payment_reference: `PAY-ENG-${fx.runId}`,
    });
    expect(error?.message ?? "").toMatch(/FORBIDDEN/i);
  });

  it("second valid partial payment works", async () => {
    if (!phase3Ready || !paymentFlowInvoiceId) return;
    const finance = financeClient;
    const { error } = await finance.rpc("record_supplier_payment", {
      p_invoice_id: paymentFlowInvoiceId,
      p_amount: 300,
      p_payment_date: new Date().toISOString().slice(0, 10),
      p_payment_reference: `PAY-P2-${fx.runId}`,
    });
    expect(error).toBeNull();
  });

  it("payment cannot exceed invoice total", async () => {
    if (!phase3Ready || !invoiceId) return;
    const finance = financeClient;
    const { error } = await finance.rpc("record_supplier_payment", {
      p_invoice_id: invoiceId,
      p_amount: 2000,
      p_payment_date: new Date().toISOString().slice(0, 10),
      p_payment_reference: `PAY-OVER-${fx.runId}`,
    });
    expect(error?.message ?? "").toMatch(/exceeds invoice/i);
  });

  it("exact remaining balance payment moves invoice to PAID", async () => {
    if (!phase3Ready || !paymentFlowInvoiceId) return;
    const finance = financeClient;
    const { error } = await finance.rpc("record_supplier_payment", {
      p_invoice_id: paymentFlowInvoiceId,
      p_amount: 300,
      p_payment_date: new Date().toISOString().slice(0, 10),
      p_payment_reference: `PAY-P3-${fx.runId}`,
    });
    expect(error).toBeNull();

    const admin = adminClient();
    const { data } = await admin
      .from("supplier_invoices")
      .select("status")
      .eq("id", paymentFlowInvoiceId)
      .single();
    expect(data?.status).toBe("paid");
  });

  it("duplicate payment reference blocked", async () => {
    if (!phase3Ready || !paymentFlowInvoiceId) return;
    const finance = financeClient;
    const { error } = await finance.rpc("record_supplier_payment", {
      p_invoice_id: paymentFlowInvoiceId,
      p_amount: 1,
      p_payment_date: new Date().toISOString().slice(0, 10),
      p_payment_reference: `PAY-P1-${fx.runId}`,
    });
    expect(error).not.toBeNull();
  });

  it("concurrent overpayment is prevented", async () => {
    if (!phase3Ready || !concurrentInvoiceId) return;
    const finance = financeClient;
    const results = await Promise.all([
      finance.rpc("record_supplier_payment", {
        p_invoice_id: concurrentInvoiceId,
        p_amount: 600,
        p_payment_date: new Date().toISOString().slice(0, 10),
        p_payment_reference: `PAY-C1-${fx.runId}`,
      }),
      finance.rpc("record_supplier_payment", {
        p_invoice_id: concurrentInvoiceId,
        p_amount: 600,
        p_payment_date: new Date().toISOString().slice(0, 10),
        p_payment_reference: `PAY-C2-${fx.runId}`,
      }),
    ]);

    const messages = results.map((r) => r.error?.message ?? "ok");
    const successes = messages.filter((m) => m === "ok").length;
    const blocked = messages.filter((m) => /exceeds invoice/i.test(m)).length;
    expect(successes).toBe(1);
    expect(blocked).toBe(1);

    const admin = adminClient();
    const { data: pays } = await admin
      .from("supplier_payments")
      .select("amount")
      .eq("supplier_invoice_id", concurrentInvoiceId);
    const totalPaid = (pays ?? []).reduce((s, p) => s + Number(p.amount), 0);
    expect(totalPaid).toBeLessThanOrEqual(1000);
  });

  it("approve PR from unified approval updates PR status", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { data: prNum } = await adminAuthedClient.rpc("generate_commercial_number", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_doc_type: "PR",
    });
    const { data: pr } = await admin
      .from("purchase_requests")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        pr_number: prNum ?? `PR-APP-${fx.runId}`,
        requested_by: fx.users.engineer.id,
        justification: "Approval sync approve test",
        status: "under_review",
        created_by: fx.users.engineer.id,
      })
      .select("id")
      .single();
    const approval = await createApprovalRequestFixture({
      entityType: "purchase_request",
      entityId: pr!.id,
      approverId: fx.users.admin.id,
      title: "Approve PR",
    });
    await admin.from("purchase_requests").update({ approval_request_id: approval.requestId }).eq("id", pr!.id);

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "A",
      p_comment: "approved",
    });
    expect(error).toBeNull();

    const { data: updated } = await admin
      .from("purchase_requests")
      .select("status, approved_at")
      .eq("id", pr!.id)
      .single();
    expect(updated?.status).toBe("approved");
    expect(updated?.approved_at).toBeTruthy();
  });

  it("reject PR from unified approval updates PR status", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { data: pr } = await admin
      .from("purchase_requests")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        pr_number: `PR-REJ-${fx.runId}-${Date.now()}`,
        requested_by: fx.users.engineer.id,
        justification: "Approval sync reject test",
        status: "under_review",
        created_by: fx.users.engineer.id,
      })
      .select("id")
      .single();
    const approval = await createApprovalRequestFixture({
      entityType: "purchase_request",
      entityId: pr!.id,
      approverId: fx.users.admin.id,
      title: "Reject PR",
    });
    await admin.from("purchase_requests").update({ approval_request_id: approval.requestId }).eq("id", pr!.id);

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "D",
      p_comment: "rejected",
    });
    expect(error).toBeNull();

    const { data: updated } = await admin
      .from("purchase_requests")
      .select("status, rejected_at")
      .eq("id", pr!.id)
      .single();
    expect(updated?.status).toBe("rejected");
    expect(updated?.rejected_at).toBeTruthy();
  });

  it("intermediate approval step does not prematurely finalize PR", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { data: pr } = await admin
      .from("purchase_requests")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        pr_number: `PR-SEQ-${fx.runId}-${Date.now()}`,
        requested_by: fx.users.engineer.id,
        justification: "Sequential approval test",
        status: "under_review",
        created_by: fx.users.engineer.id,
      })
      .select("id")
      .single();
    const dueAt = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();
    const { data: request } = await admin
      .from("approval_requests")
      .insert({
        organization_id: fx.orgAId,
        entity_type: "purchase_request",
        entity_id: pr!.id,
        title: "Sequential PR",
        status: "in_progress",
        mode: "sequential",
        requested_by: fx.users.admin.id,
        due_at: dueAt,
        warning_at: new Date(Date.parse(dueAt) - 24 * 60 * 60 * 1000).toISOString(),
      })
      .select("id")
      .single();
    await admin.from("approval_steps").insert([
      {
        organization_id: fx.orgAId,
        request_id: request!.id,
        sequence: 1,
        approver_type: "user",
        user_id: fx.users.admin.id,
        status: "in_progress",
        due_at: dueAt,
      },
      {
        organization_id: fx.orgAId,
        request_id: request!.id,
        sequence: 2,
        approver_type: "user",
        user_id: fx.users.pm.id,
        status: "pending",
        due_at: dueAt,
      },
    ]);
    await admin.from("purchase_requests").update({ approval_request_id: request!.id }).eq("id", pr!.id);

    const { data: firstStep } = await admin
      .from("approval_steps")
      .select("id")
      .eq("request_id", request!.id)
      .eq("sequence", 1)
      .single();
    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: request!.id,
      p_step_id: firstStep!.id,
      p_official_code: "A",
      p_comment: "step one ok",
    });
    expect(error).toBeNull();

    const { data: updatedPr } = await admin.from("purchase_requests").select("status").eq("id", pr!.id).single();
    const { data: updatedReq } = await admin.from("approval_requests").select("status").eq("id", request!.id).single();
    const { data: nextStep } = await admin
      .from("approval_steps")
      .select("status")
      .eq("request_id", request!.id)
      .eq("sequence", 2)
      .single();
    expect(updatedPr?.status).toBe("under_review");
    expect(updatedReq?.status).toBe("in_progress");
    expect(nextStep?.status).toBe("in_progress");
  });

  it("approve PO from unified approval keeps PO unissued", async () => {
    if (!phase3Ready || !draftPoId) return;
    const admin = adminClient();
    const approval = await createApprovalRequestFixture({
      entityType: "purchase_order",
      entityId: draftPoId,
      approverId: fx.users.admin.id,
      title: "Approve PO",
    });
    await admin.from("purchase_orders").update({ status: "pending_approval", approval_request_id: approval.requestId }).eq("id", draftPoId);

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "A",
      p_comment: "approved",
    });
    expect(error).toBeNull();

    const { data: updated } = await admin
      .from("purchase_orders")
      .select("status, issued_at")
      .eq("id", draftPoId)
      .single();
    expect(updated?.status).toBe("approved");
    expect(updated?.issued_at).toBeNull();
  });

  it("approve supplier invoice via unified approval sets approved_for_payment", async () => {
    if (!phase3Ready || !invoiceId) return;
    const admin = adminClient();
    const { data: inv } = await admin
      .from("supplier_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        supplier_id: supplierId,
        invoice_number: `INV-APP-${fx.runId}-${Date.now()}`,
        invoice_date: new Date().toISOString().slice(0, 10),
        currency: "SAR",
        subtotal: 100,
        vat_amount: 15,
        total: 115,
        status: "under_review",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    const approval = await createApprovalRequestFixture({
      entityType: "supplier_invoice",
      entityId: inv!.id,
      approverId: fx.users.admin.id,
      title: "Approve invoice",
    });

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "A",
      p_comment: "approved",
    });
    expect(error).toBeNull();

    const { data: updated } = await admin.from("supplier_invoices").select("status").eq("id", inv!.id).single();
    expect(updated?.status).toBe("approved_for_payment");
  });

  it("approve variation via unified approval updates status and commercial summary", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { data: contract } = await admin
      .from("project_contracts")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_number: `CON-${fx.runId}-${Date.now()}`,
        client_name: "Test Client",
        contract_value: 100000,
        currency: "SAR",
        start_date: new Date().toISOString().slice(0, 10),
        status: "active",
        created_by: fx.users.admin.id,
      })
      .select("id")
      .single();
    await admin.from("project_budgets").upsert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      currency: "SAR",
      original_budget_amount: 100000,
      approved_variation_amount: 0,
      status: "active",
      created_by: fx.users.admin.id,
    });
    const { data: variation } = await admin
      .from("variations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contract!.id,
        vo_number: `VO-${fx.runId}-${Date.now()}`,
        description: "Unified approval variation test",
        cost_impact: 5000,
        submitted_amount: 5000,
        status: "submitted",
        created_by: fx.users.admin.id,
      })
      .select("id")
      .single();
    const approval = await createApprovalRequestFixture({
      entityType: "variation",
      entityId: variation!.id,
      approverId: fx.users.admin.id,
      title: "Approve variation",
    });
    await admin.from("variations").update({ approval_request_id: approval.requestId }).eq("id", variation!.id);

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "A",
      p_comment: "approved",
    });
    expect(error).toBeNull();

    const { data: updatedVariation } = await admin
      .from("variations")
      .select("status, approved_amount")
      .eq("id", variation!.id)
      .single();
    expect(updatedVariation?.status).toBe("approved");
    expect(Number(updatedVariation?.approved_amount)).toBe(5000);

    const { data: summary } = await adminAuthedClient.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(Number(summary?.approved_variations ?? 0)).toBeGreaterThanOrEqual(5000);
  });

  it("approve PR with official code B sets approved", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { data: pr } = await admin
      .from("purchase_requests")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        pr_number: `PR-B-${fx.runId}-${Date.now()}`,
        requested_by: fx.users.engineer.id,
        justification: "Approval sync B test",
        status: "under_review",
        created_by: fx.users.engineer.id,
      })
      .select("id")
      .single();
    const approval = await createApprovalRequestFixture({
      entityType: "purchase_request",
      entityId: pr!.id,
      approverId: fx.users.admin.id,
      title: "Approve PR as noted",
    });
    await admin.from("purchase_requests").update({ approval_request_id: approval.requestId }).eq("id", pr!.id);

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "B",
      p_comment: "approved as noted",
    });
    expect(error).toBeNull();

    const { data: updated } = await admin
      .from("purchase_requests")
      .select("status, approved_at")
      .eq("id", pr!.id)
      .single();
    expect(updated?.status).toBe("approved");
    expect(updated?.approved_at).toBeTruthy();
  });

  it("revise PR with official code C returns entity to draft", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { data: pr } = await admin
      .from("purchase_requests")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        pr_number: `PR-C-${fx.runId}-${Date.now()}`,
        requested_by: fx.users.engineer.id,
        justification: "Approval sync C test",
        status: "under_review",
        created_by: fx.users.engineer.id,
      })
      .select("id")
      .single();
    const approval = await createApprovalRequestFixture({
      entityType: "purchase_request",
      entityId: pr!.id,
      approverId: fx.users.admin.id,
      title: "Revise PR",
    });
    await admin.from("purchase_requests").update({ approval_request_id: approval.requestId }).eq("id", pr!.id);

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "C",
      p_comment: "revise",
    });
    expect(error).toBeNull();

    const { data: updated } = await admin
      .from("purchase_requests")
      .select("status, approved_at, rejected_at")
      .eq("id", pr!.id)
      .single();
    expect(updated?.status).toBe("draft");
    expect(updated?.approved_at).toBeNull();
    expect(updated?.rejected_at).toBeNull();
  });

  it("unsupported entity type fails controlled without deciding", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const approval = await createApprovalRequestFixture({
      entityType: "document",
      entityId: crypto.randomUUID(),
      approverId: fx.users.admin.id,
      title: "Unsupported entity",
    });

    const { error } = await adminAuthedClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "A",
      p_comment: "should fail",
    });
    expect(error?.message ?? "").toMatch(/NOT_SUPPORTED/i);

    const { data: request } = await admin
      .from("approval_requests")
      .select("status")
      .eq("id", approval.requestId)
      .single();
    const { data: actions } = await admin.from("approval_actions").select("id").eq("request_id", approval.requestId);
    expect(request?.status).toBe("in_progress");
    expect(actions ?? []).toHaveLength(0);
  });

  it("unauthorized approver is denied without mutating the entity", async () => {
    if (!phase3Ready) return;
    const admin = adminClient();
    const { data: pr } = await admin
      .from("purchase_requests")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        pr_number: `PR-UNAUTH-${fx.runId}-${Date.now()}`,
        requested_by: fx.users.engineer.id,
        justification: "Unauthorized approver test",
        status: "under_review",
        created_by: fx.users.engineer.id,
      })
      .select("id")
      .single();
    const approval = await createApprovalRequestFixture({
      entityType: "purchase_request",
      entityId: pr!.id,
      approverId: fx.users.admin.id,
      title: "Admin-only PR step",
    });
    await admin.from("purchase_requests").update({ approval_request_id: approval.requestId }).eq("id", pr!.id);

    const { error } = await engineerClient.rpc("decide_entity_approval", {
      p_request_id: approval.requestId,
      p_step_id: approval.stepId,
      p_official_code: "A",
      p_comment: "not my step",
    });
    expect(error?.message ?? "").toMatch(/FORBIDDEN/i);

    const { data: updated } = await admin.from("purchase_requests").select("status").eq("id", pr!.id).single();
    const { data: request } = await admin
      .from("approval_requests")
      .select("status")
      .eq("id", approval.requestId)
      .single();
    expect(updated?.status).toBe("under_review");
    expect(request?.status).toBe("in_progress");
  });

  it("engineer cannot access commercial summary RPC", async () => {
    if (!phase3Ready) return;
    const engineer = engineerClient;
    const { error } = await engineer.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(error?.message ?? "").toMatch(/FORBIDDEN/i);
  });
});
