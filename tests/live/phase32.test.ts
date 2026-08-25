import "../setup-env";
import { describe, expect, it, beforeAll } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  adminClient,
  liveTestConfigured,
  provisionLiveFixture,
  signInAs,
  type LiveFixture,
} from "./helpers";

const configured = liveTestConfigured();

describe.skipIf(!configured)("live Phase 3.2 client revenue integrity", () => {
  let fx: LiveFixture;
  let phase32Ready = false;
  let financeClient: SupabaseClient;
  let engineerClient: SupabaseClient;
  let contractId: string;
  let valuationId: string;
  let clientInvoiceId: string;
  let concurrentInvoiceId: string;
  let variationId: string;
  const originalContractValue = 500_000;
  const submittedClaim = 115_000;
  const certifiedAmount = 80_000;

  beforeAll(async () => {
    fx = await provisionLiveFixture();
    const admin = adminClient();

    const { error: tableErr } = await admin.from("entity_documents").select("id").limit(1);
    // 050 helpers required; 051 semantics detected via issue on invoiced valuation path in tests.
    const { error: helperErr } = await admin.rpc("can_issue_client_invoice", {
      p_project_id: "00000000-0000-0000-0000-000000000001",
      p_organization_id: fx.orgAId,
    });
    phase32Ready = !tableErr && !(helperErr?.message ?? "").match(/could not find|does not exist|schema cache/i);
    if (!phase32Ready) {
      console.warn("[live-test] Apply migrations 050–051 (phase3_fix_050/051.sql) then re-run.");
      return;
    }

    financeClient = await signInAs(fx.users.finance.email, fx.users.finance.password);
    engineerClient = await signInAs(fx.users.engineer.email, fx.users.engineer.password);

    const { data: contract, error: contractErr } = await admin
      .from("project_contracts")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        client_name: `Client ${fx.runId}`,
        contract_number: `CON-${fx.runId}`,
        contract_value: originalContractValue,
        currency: "SAR",
        status: "active",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    if (contractErr || !contract) throw new Error(`contract fixture: ${contractErr?.message}`);
    contractId = contract.id;

    const { data: valNum } = await financeClient.rpc("generate_commercial_number", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_doc_type: "VAL",
    });
    const { data: val, error: valErr } = await admin
      .from("client_valuations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_number: valNum ?? `VAL-${fx.runId}`,
        gross_work_value: 100_000,
        variations_amount: 0,
        advance_recovery: 0,
        previous_certified_amount: 0,
        total_claim: submittedClaim,
        current_claim_amount: 100_000,
        vat_amount: 15_000,
        status: "under_client_review",
        created_by: fx.users.finance.id,
      })
      .select("id, total_claim")
      .single();
    if (valErr || !val) throw new Error(`valuation fixture: ${valErr?.message}`);
    valuationId = val.id;

    const { data: certified, error: certErr } = await financeClient.rpc(
      "record_client_valuation_certification",
      {
        p_valuation_id: valuationId,
        p_client_reference: `CERT-${fx.runId}`,
        p_certified_amount: certifiedAmount,
        p_certification_date: "2026-01-15",
        p_comments: "partial cert live test",
      },
    );
    if (certErr) throw new Error(`certification fixture: ${certErr.message}`);
    if (Number(certified?.certified_amount) !== certifiedAmount) {
      throw new Error(`certification fixture: expected certified_amount ${certifiedAmount}, got ${certified?.certified_amount}`);
    }

    const { data: inv, error: invErr } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_id: valuationId,
        invoice_number: `CINV-${fx.runId}`,
        invoice_date: "2026-01-20",
        due_date: "2026-02-20",
        amount: 69_565.22,
        vat_amount: 10_434.78,
        total: certifiedAmount,
        status: "draft",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    if (invErr || !inv) throw new Error(`invoice fixture: ${invErr?.message}`);
    clientInvoiceId = inv.id;

    const { error: issueErr } = await financeClient.rpc("issue_client_invoice", {
      p_invoice_id: clientInvoiceId,
    });
    if (issueErr) throw new Error(`issue fixture: ${issueErr.message}`);

    const { data: issued } = await admin
      .from("client_invoices")
      .select("status, issued_at")
      .eq("id", clientInvoiceId)
      .single();
    if (issued?.status !== "issued" || !issued.issued_at) {
      throw new Error(`issue fixture: invoice not issued (status=${issued?.status})`);
    }

    const { data: cInv, error: cInvErr } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        invoice_number: `CINV-CONC-${fx.runId}`,
        invoice_date: "2026-01-20",
        due_date: "2026-02-20",
        amount: 869.57,
        vat_amount: 130.43,
        total: 1000,
        status: "issued",
        issued_at: new Date().toISOString(),
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    if (cInvErr || !cInv) throw new Error(`concurrent invoice fixture: ${cInvErr?.message}`);
    concurrentInvoiceId = cInv.id;

    const { data: voNum } = await financeClient.rpc("generate_commercial_number", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_doc_type: "VO",
    });
    const { data: vo, error: voErr } = await admin
      .from("variations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        vo_number: voNum ?? `VO-${fx.runId}`,
        source: "CLIENT_REQUEST",
        description: "Live VO partial",
        requested_amount: 100_000,
        submitted_amount: 100_000,
        cost_impact: 100_000,
        status: "submitted",
        created_by: fx.users.pm.id,
      })
      .select("id")
      .single();
    if (voErr || !vo) throw new Error(`variation fixture: ${voErr?.message}`);
    variationId = vo.id;
  }, 120_000);

  it("preserves submitted claim when certified lower", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const { data } = await admin
      .from("client_valuations")
      .select("total_claim, certified_amount, rejected_amount, status")
      .eq("id", valuationId)
      .single();
    expect(Number(data?.total_claim)).toBe(submittedClaim);
    expect(Number(data?.certified_amount)).toBe(certifiedAmount);
    expect(Number(data?.rejected_amount)).toBe(submittedClaim - certifiedAmount);
    expect(data?.status).toBe("invoiced"); // certified then issued in beforeAll
  });

  it("full certification sets certified status", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const claim = 50_000;
    const { data: val } = await admin
      .from("client_valuations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_number: `VAL-FULL-${fx.runId}-${Date.now()}`,
        gross_work_value: claim,
        total_claim: claim,
        current_claim_amount: claim,
        status: "submitted",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { data, error } = await financeClient.rpc("record_client_valuation_certification", {
      p_valuation_id: val!.id,
      p_client_reference: `CERT-FULL-${Date.now()}`,
      p_certified_amount: claim,
    });
    expect(error).toBeNull();
    expect(data?.status).toBe("certified");
    expect(Number(data?.certified_amount)).toBe(claim);
    expect(Number(data?.rejected_amount)).toBe(0);
    expect(Number(data?.total_claim)).toBe(claim);
  });

  it("zero certification rejects while preserving claim", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const claim = 25_000;
    const { data: val } = await admin
      .from("client_valuations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_number: `VAL-REJ-${fx.runId}-${Date.now()}`,
        gross_work_value: claim,
        total_claim: claim,
        current_claim_amount: claim,
        status: "under_client_review",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { data, error } = await financeClient.rpc("record_client_valuation_certification", {
      p_valuation_id: val!.id,
      p_client_reference: `CERT-REJ-${Date.now()}`,
      p_certified_amount: 0,
    });
    expect(error).toBeNull();
    expect(data?.status).toBe("rejected");
    expect(Number(data?.total_claim)).toBe(claim);
    expect(Number(data?.certified_amount)).toBe(0);
    expect(Number(data?.rejected_amount)).toBe(claim);
  });

  it("blocks invoice exceeding certified amount at issue", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    // valuationId was partially certified then already issued once in beforeAll
    // (status=invoiced). Further issue must still enforce certified remaining capacity.
    const { data: overInv, error: insertErr } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_id: valuationId,
        invoice_number: `CINV-OVER-${Date.now()}`,
        invoice_date: "2026-01-21",
        amount: 100_000,
        vat_amount: 15_000,
        total: 115_000,
        status: "draft",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();
    expect(insertErr).toBeNull();

    const { error } = await financeClient.rpc("issue_client_invoice", {
      p_invoice_id: overInv!.id,
    });
    expect(error?.message ?? "").toMatch(/CLIENT_INVOICE_EXCEEDS_CERTIFIED|exceeds certified/i);
  });

  it("partially certified valuation can invoice up to certified amount", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const claim = 100_000;
    const certified = 80_000;
    const { data: val } = await admin
      .from("client_valuations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_number: `VAL-PCERT-${fx.runId}-${Date.now()}`,
        gross_work_value: claim,
        total_claim: claim,
        current_claim_amount: claim,
        status: "under_client_review",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { error: certErr } = await financeClient.rpc("record_client_valuation_certification", {
      p_valuation_id: val!.id,
      p_client_reference: `CERT-PC-${Date.now()}`,
      p_certified_amount: certified,
    });
    expect(certErr).toBeNull();

    const { data: afterCert } = await admin
      .from("client_valuations")
      .select("status, certified_amount, total_claim")
      .eq("id", val!.id)
      .single();
    expect(afterCert?.status).toBe("partially_certified");
    expect(Number(afterCert?.certified_amount)).toBe(certified);

    const { data: okInv } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_id: val!.id,
        invoice_number: `CINV-PC-OK-${Date.now()}`,
        invoice_date: "2026-01-22",
        amount: certified,
        vat_amount: 0,
        total: certified,
        status: "draft",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { error: issueOk } = await financeClient.rpc("issue_client_invoice", {
      p_invoice_id: okInv!.id,
    });
    expect(issueOk).toBeNull();

    const { data: overInv } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_id: val!.id,
        invoice_number: `CINV-PC-OVER-${Date.now()}`,
        invoice_date: "2026-01-22",
        amount: 1,
        vat_amount: 0,
        total: 1,
        status: "draft",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { error: issueOver } = await financeClient.rpc("issue_client_invoice", {
      p_invoice_id: overInv!.id,
    });
    expect(issueOver?.message ?? "").toMatch(/CLIENT_INVOICE_EXCEEDS_CERTIFIED|exceeds certified/i);
  });

  it("rejected and submitted valuations cannot create normal invoice", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();

    const { data: rejected } = await admin
      .from("client_valuations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_number: `VAL-NOINV-R-${Date.now()}`,
        gross_work_value: 10_000,
        total_claim: 10_000,
        status: "rejected",
        certified_amount: 0,
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { data: submitted } = await admin
      .from("client_valuations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        valuation_number: `VAL-NOINV-S-${Date.now()}`,
        gross_work_value: 10_000,
        total_claim: 10_000,
        status: "submitted",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    for (const valuation_id of [rejected!.id, submitted!.id]) {
      const { data: draft } = await admin
        .from("client_invoices")
        .insert({
          organization_id: fx.orgAId,
          project_id: fx.projectId,
          contract_id: contractId,
          valuation_id,
          invoice_number: `CINV-NOINV-${valuation_id.slice(0, 8)}-${Date.now()}`,
          invoice_date: "2026-01-22",
          amount: 100,
          vat_amount: 0,
          total: 100,
          status: "draft",
          created_by: fx.users.finance.id,
        })
        .select("id")
        .single();
      const { error } = await financeClient.rpc("issue_client_invoice", { p_invoice_id: draft!.id });
      expect(error?.message ?? "").toMatch(/CLIENT_VALUATION_NOT_CERTIFIED|not certified/i);
    }
  });

  it("engineer cannot issue client invoice", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const { data: draft } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        invoice_number: `CINV-ENG-${Date.now()}`,
        invoice_date: "2026-01-21",
        amount: 100,
        vat_amount: 15,
        total: 115,
        status: "draft",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { error } = await engineerClient.rpc("issue_client_invoice", {
      p_invoice_id: draft!.id,
    });
    expect(error?.message ?? "").toMatch(/FORBIDDEN/i);
  });

  it("client payment partial then final reaches PAID", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const { error: e1 } = await financeClient.rpc("record_client_payment", {
      p_invoice_id: clientInvoiceId,
      p_amount: 600,
      p_received_date: "2026-02-01",
      p_reference: `RCP-A-${fx.runId}`,
    });
    expect(e1).toBeNull();

    const { data: mid } = await admin.from("client_invoices").select("status").eq("id", clientInvoiceId).single();
    expect(mid?.status).toBe("partially_paid");

    const { error: e2 } = await financeClient.rpc("record_client_payment", {
      p_invoice_id: clientInvoiceId,
      p_amount: 79_400,
      p_received_date: "2026-02-10",
      p_reference: `RCP-B-${fx.runId}`,
    });
    expect(e2).toBeNull();

    const { data: inv } = await admin.from("client_invoices").select("status").eq("id", clientInvoiceId).single();
    expect(inv?.status).toBe("paid");
  });

  it("blocks third over-collection receipt", async () => {
    if (!phase32Ready) return;
    const { error } = await financeClient.rpc("record_client_payment", {
      p_invoice_id: clientInvoiceId,
      p_amount: 1,
      p_received_date: "2026-02-11",
      p_reference: `RCP-C-${fx.runId}`,
    });
    expect(error?.message ?? "").toMatch(/CLIENT_PAYMENT_EXCEEDS_OUTSTANDING|exceeds/i);
  });

  it("draft invoice payment is not payable", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const { data: draft } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        invoice_number: `CINV-DRAFT-PAY-${Date.now()}`,
        invoice_date: "2026-01-20",
        amount: 500,
        vat_amount: 0,
        total: 500,
        status: "draft",
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const { error } = await financeClient.rpc("record_client_payment", {
      p_invoice_id: draft!.id,
      p_amount: 100,
      p_received_date: "2026-02-01",
      p_reference: `RCP-DRAFT-${fx.runId}-${Date.now()}`,
    });
    expect(error?.message ?? "").toMatch(/CLIENT_INVOICE_NOT_PAYABLE/i);
  });

  it("duplicate payment reference is blocked", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const { data: inv } = await admin
      .from("client_invoices")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        invoice_number: `CINV-DUP-${Date.now()}`,
        invoice_date: "2026-01-20",
        amount: 100,
        vat_amount: 0,
        total: 100,
        status: "issued",
        issued_at: new Date().toISOString(),
        created_by: fx.users.finance.id,
      })
      .select("id")
      .single();

    const ref = `RCP-DUP-${fx.runId}`;
    const { error: e1 } = await financeClient.rpc("record_client_payment", {
      p_invoice_id: inv!.id,
      p_amount: 40,
      p_received_date: "2026-02-01",
      p_reference: ref,
    });
    expect(e1).toBeNull();

    const { error: e2 } = await financeClient.rpc("record_client_payment", {
      p_invoice_id: inv!.id,
      p_amount: 40,
      p_received_date: "2026-02-02",
      p_reference: ref,
    });
    expect(e2?.message ?? "").toMatch(/CLIENT_PAYMENT_DUPLICATE_REFERENCE|duplicate/i);
  });

  it("concurrent client payments — only one succeeds when total would exceed", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const results = await Promise.all([
      financeClient.rpc("record_client_payment", {
        p_invoice_id: concurrentInvoiceId,
        p_amount: 600,
        p_received_date: "2026-02-01",
        p_reference: `CONC-A-${Date.now()}`,
      }),
      financeClient.rpc("record_client_payment", {
        p_invoice_id: concurrentInvoiceId,
        p_amount: 600,
        p_received_date: "2026-02-01",
        p_reference: `CONC-B-${Date.now()}`,
      }),
    ]);
    const successes = results.filter((r) => !r.error).length;
    expect(successes).toBe(1);

    const { data: pays } = await admin
      .from("client_payments")
      .select("amount")
      .eq("client_invoice_id", concurrentInvoiceId);
    const paid = (pays ?? []).reduce((s, p) => s + Number(p.amount), 0);
    expect(paid).toBeLessThanOrEqual(1000.001);
  });

  it("partial variation approval uses approved amount only in summary", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const { error } = await financeClient.rpc("approve_variation", {
      p_variation_id: variationId,
      p_approved_amount: 70_000,
    });
    expect(error).toBeNull();

    const { data: vo } = await admin
      .from("variations")
      .select("status, requested_amount, submitted_amount, approved_amount")
      .eq("id", variationId)
      .single();
    expect(vo?.status).toBe("partially_approved");
    expect(Number(vo?.requested_amount)).toBe(100_000);
    expect(Number(vo?.submitted_amount)).toBe(100_000);
    expect(Number(vo?.approved_amount)).toBe(70_000);

    const { data: contract } = await admin
      .from("project_contracts")
      .select("contract_value")
      .eq("id", contractId)
      .single();
    expect(Number(contract?.contract_value)).toBe(originalContractValue);

    const { data: summary, error: sumErr } = await financeClient.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(sumErr).toBeNull();
    expect(Number(summary?.original_contract_value ?? 0)).toBeGreaterThanOrEqual(originalContractValue);
    expect(Number(summary?.approved_variations ?? 0)).toBeGreaterThanOrEqual(70_000);
    expect(Number(summary?.revised_contract_value ?? 0)).toBeGreaterThanOrEqual(
      originalContractValue + 70_000,
    );
  });

  it("rejected variation has zero commercial impact", async () => {
    if (!phase32Ready) return;
    const admin = adminClient();
    const { data: before } = await financeClient.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    const approvedBefore = Number(before?.approved_variations ?? 0);

    const { data: vo } = await admin
      .from("variations")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        contract_id: contractId,
        vo_number: `VO-REJ-${fx.runId}-${Date.now()}`,
        source: "OTHER",
        description: "Rejected VO",
        requested_amount: 40_000,
        submitted_amount: 40_000,
        cost_impact: 40_000,
        status: "submitted",
        created_by: fx.users.pm.id,
      })
      .select("id")
      .single();

    const { error } = await financeClient.rpc("approve_variation", {
      p_variation_id: vo!.id,
      p_approved_amount: 0,
    });
    expect(error).toBeNull();

    const { data: updated } = await admin.from("variations").select("status, approved_amount").eq("id", vo!.id).single();
    expect(updated?.status).toBe("rejected");
    expect(Number(updated?.approved_amount)).toBe(0);

    const { data: after } = await financeClient.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(Number(after?.approved_variations ?? 0)).toBe(approvedBefore);
  });

  it("engineer denied commercial summary and variation approve", async () => {
    if (!phase32Ready) return;
    const { error: sumErr } = await engineerClient.rpc("compute_project_commercial_summary", {
      p_project_id: fx.projectId,
    });
    expect(sumErr?.message ?? "").toMatch(/FORBIDDEN/i);

    const { error: voErr } = await engineerClient.rpc("approve_variation", {
      p_variation_id: variationId,
      p_approved_amount: 1,
    });
    expect(voErr?.message ?? "").toMatch(/FORBIDDEN/i);
  });

  it("issued client invoice is immutable for finance user", async () => {
    if (!phase32Ready) return;
    const { error } = await financeClient
      .from("client_invoices")
      .update({ total: 1 })
      .eq("id", clientInvoiceId);
    expect(error?.message ?? "").toMatch(/immutable/i);
  });
});
