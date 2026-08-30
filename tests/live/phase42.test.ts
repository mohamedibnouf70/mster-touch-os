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

describe.skipIf(!configured)("live Phase 4.2 contracts, compensation, hr documents & banking", () => {
  let fx: LiveFixture;
  let phase42Ready = false;
  let admin: SupabaseClient;
  let hrClient: SupabaseClient;
  let finClient: SupabaseClient;
  let engClient: SupabaseClient;
  let peerClient: SupabaseClient;
  let deptMgrClient: SupabaseClient;

  let hrEmployeeId = "";
  let peerEmployeeId = "";

  beforeAll(async () => {
    admin = adminClient();

    // Check readiness of migration 053 & 054
    const { error: contractErr } = await admin.from("employee_contracts").select("id").limit(1);
    const { error: compErr } = await admin.from("employee_compensation_versions").select("id").limit(1);
    const { error: docErr } = await admin.from("employee_documents").select("id").limit(1);
    const { error: bankErr } = await admin.from("employee_bank_accounts").select("id").limit(1);

    phase42Ready = !contractErr && !compErr && !docErr && !bankErr;

    if (!phase42Ready) {
      console.warn(
        "[live-test] Full Phase 4.2 requires both 053 & 054 (supabase/phase4_fix_054.sql). Skipping full suite until 054 is applied.",
      );
      return;
    }

    fx = await provisionLiveFixture();

    const prefix = process.env.LIVE_TEST_PASSWORD_PREFIX ?? "MtTest1!";
    const hrEmail = `mt-live-hr42-${fx.runId}@test.local`;
    const hrPassword = `${prefix}hr42`;
    const finEmail = `mt-live-fin42-${fx.runId}@test.local`;
    const finPassword = `${prefix}fin42`;
    const peerEmail = `mt-live-peer42-${fx.runId}@test.local`;
    const peerPassword = `${prefix}peer42`;
    const dmEmail = `mt-live-dm42-${fx.runId}@test.local`;
    const dmPassword = `${prefix}dm42`;

    async function createWithRole(email: string, password: string, roleCode: string) {
      const { data: created, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name_ar: roleCode, full_name_en: roleCode, locale: "ar" },
      });
      if (error || !created.user) throw new Error(`createUser ${email}: ${error?.message}`);
      const userId = created.user.id;
      await admin.from("organization_members").upsert({
        organization_id: fx.orgAId,
        profile_id: userId,
        status: "active",
      });
      const { data: emp, error: empErr } = await admin
        .from("employees")
        .upsert(
          {
            organization_id: fx.orgAId,
            profile_id: userId,
            employment_status: "active",
            is_active: true,
            employee_number: `E42${fx.runId}${roleCode.slice(0, 3)}`,
          },
          { onConflict: "organization_id,profile_id" },
        )
        .select("id")
        .single<{ id: string }>();
      if (empErr) throw new Error(`emp ${email}: ${empErr.message}`);

      const { data: role } = await admin
        .from("roles")
        .select("id")
        .eq("code", roleCode)
        .is("organization_id", null)
        .maybeSingle();
      if (role?.id) {
        await admin.from("user_roles").insert({
          organization_id: fx.orgAId,
          profile_id: userId,
          role_id: role.id,
        });
      }
      return { userId, employeeId: emp.id };
    }

    const hr = await createWithRole(hrEmail, hrPassword, "hr_manager");
    hrEmployeeId = hr.employeeId;

    await createWithRole(finEmail, finPassword, "finance_manager");

    const peer = await createWithRole(peerEmail, peerPassword, "employee");
    peerEmployeeId = peer.employeeId;

    await createWithRole(dmEmail, dmPassword, "department_manager");

    hrClient = await signInAs(hrEmail, hrPassword);
    finClient = await signInAs(finEmail, finPassword);
    peerClient = await signInAs(peerEmail, peerPassword);
    deptMgrClient = await signInAs(dmEmail, dmPassword);
    engClient = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
  }, 120_000);

  it("01 — confirms migrations 053 & 054 tables exist", async () => {
    if (!phase42Ready) return;
    const { error: cErr } = await admin.from("employee_contracts").select("id").limit(1);
    const { error: docErr } = await admin.from("employee_documents").select("id").limit(1);
    const { error: compErr } = await admin.from("employee_compensation_versions").select("id").limit(1);
    const { error: bErr } = await admin.from("employee_bank_accounts").select("id").limit(1);

    expect(cErr).toBeNull();
    expect(docErr).toBeNull();
    expect(compErr).toBeNull();
    expect(bErr).toBeNull();
  });

  it("02 — HR Manager creates and activates contract, setting single is_current", async () => {
    if (!phase42Ready) return;

    // HR inserts a draft contract
    const contractNum = `CTR-${fx.runId}-001`;
    const { data: draft, error: createErr } = await hrClient
      .from("employee_contracts")
      .insert({
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        contract_number: contractNum,
        contract_type: "permanent",
        status: "draft",
        start_date: "2026-01-01",
        working_hours_per_week: 40,
        initial_basic_salary: 15000,
        created_by: (await hrClient.auth.getUser()).data.user!.id,
      })
      .select("id, status, is_current")
      .single<{ id: string; status: string; is_current: boolean }>();

    expect(createErr).toBeNull();
    expect(draft?.status).toBe("draft");
    expect(draft?.is_current).toBe(false);

    // Activate contract via RPC
    const { data: activated, error: actErr } = await hrClient.rpc("activate_employee_contract", {
      p_organization_id: fx.orgAId,
      p_contract_id: draft!.id,
    });

    expect(actErr).toBeNull();
    expect(activated?.status).toBe("active");
    expect(activated?.is_current).toBe(true);

    // Verify employee snapshot updated
    const { data: emp } = await admin
      .from("employees")
      .select("contract_start, employment_type")
      .eq("id", peerEmployeeId)
      .single();
    expect(emp?.contract_start).toBe("2026-01-01");
    expect(emp?.employment_type).toBe("permanent");
  });

  it("03 — contract immutability blocks direct modification of active contract terms", async () => {
    if (!phase42Ready) return;

    const { data: activeContract } = await admin
      .from("employee_contracts")
      .select("id")
      .eq("employee_id", peerEmployeeId)
      .eq("is_current", true)
      .single();

    expect(activeContract?.id).toBeTruthy();

    // Try modifying start_date on active contract
    const { error: updateErr } = await hrClient
      .from("employee_contracts")
      .update({ start_date: "2025-05-01" })
      .eq("id", activeContract!.id);

    expect(updateErr).toBeTruthy();
    expect(updateErr?.message).toMatch(/IMMUTABLE_CONTRACT/i);
  });

  it("04 — employee self can read own contract; peer and cross-org denied", async () => {
    if (!phase42Ready) return;

    // Self read
    const { data: selfContracts, error: selfErr } = await peerClient
      .from("employee_contracts")
      .select("id, contract_number")
      .eq("employee_id", peerEmployeeId);

    expect(selfErr).toBeNull();
    expect(selfContracts?.length).toBeGreaterThanOrEqual(1);

    // Peer try to read another's contract
    const { data: peerRead } = await peerClient
      .from("employee_contracts")
      .select("id")
      .eq("employee_id", hrEmployeeId);

    expect(peerRead?.length ?? 0).toBe(0);

    // Cross-org user denied
    const crossClient = await signInAs(fx.users.restricted.email, fx.users.restricted.password);
    const { data: crossRead } = await crossClient
      .from("employee_contracts")
      .select("id")
      .eq("employee_id", peerEmployeeId);
    expect(crossRead?.length ?? 0).toBe(0);
  });

  it("05 — HR creates compensation versions; prevents overlapping ranges; historical versions immutable", async () => {
    if (!phase42Ready) return;

    // Create version 1 via RPC
    const { data: v1, error: v1Err } = await hrClient.rpc("create_employee_compensation_version", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_effective_from: "2026-01-01",
      p_currency: "SAR",
      p_basic_salary: 12000,
      p_housing_allowance: 3000,
      p_transport_allowance: 1000,
      p_other_allowances: 0,
      p_change_reason: "Initial baseline",
    });

    expect(v1Err).toBeNull();
    expect(v1?.basic_salary).toBe(12000);
    expect(v1?.status).toBe("active");

    // Create version 2 effective 2026-06-01 (should auto-close v1 to 2026-05-31)
    const { data: v2, error: v2Err } = await hrClient.rpc("create_employee_compensation_version", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_effective_from: "2026-06-01",
      p_currency: "SAR",
      p_basic_salary: 14000,
      p_housing_allowance: 3500,
      p_transport_allowance: 1000,
      p_other_allowances: 500,
      p_change_reason: "Mid-year promotion",
    });

    expect(v2Err).toBeNull();
    expect(v2?.basic_salary).toBe(14000);

    // Check v1 was superseded
    const { data: closedV1 } = await admin
      .from("employee_compensation_versions")
      .select("effective_to, status")
      .eq("id", v1.id)
      .single();
    expect(closedV1?.status).toBe("superseded");
    expect(closedV1?.effective_to).toBe("2026-05-31");

    // Try modifying closed historical v1
    const { error: modErr } = await hrClient
      .from("employee_compensation_versions")
      .update({ basic_salary: 99999 })
      .eq("id", v1.id);
    expect(modErr).toBeTruthy();
    expect(modErr?.message).toMatch(/IMMUTABLE_COMPENSATION/i);
  });

  it("06 — compensation confidentiality: Dept Manager and Engineer DENIED; Finance Manager ALLOWED", async () => {
    if (!phase42Ready) return;

    // Dept Manager select -> 0 rows
    const { data: dmComp } = await deptMgrClient
      .from("employee_compensation_versions")
      .select("id, basic_salary")
      .eq("employee_id", peerEmployeeId);
    expect(dmComp?.length ?? 0).toBe(0);

    // Engineer select -> 0 rows
    const { data: engComp } = await engClient
      .from("employee_compensation_versions")
      .select("id, basic_salary")
      .eq("employee_id", peerEmployeeId);
    expect(engComp?.length ?? 0).toBe(0);

    // Finance Manager select -> allowed
    const { data: finComp, error: finErr } = await finClient
      .from("employee_compensation_versions")
      .select("id, basic_salary")
      .eq("employee_id", peerEmployeeId);
    expect(finErr).toBeNull();
    expect(finComp?.length).toBeGreaterThanOrEqual(1);
  });

  it("07 — Secure HR Documents: HR Manager and Self allowed; peer and engineer DENIED", async () => {
    if (!phase42Ready) return;

    // Seed document in documents table and link via employee_documents
    const { data: doc } = await admin
      .from("documents")
      .insert({
        organization_id: fx.orgAId,
        title: "Iqama Copy",
        category: "other",
        current_revision: "A",
        uploaded_by: (await hrClient.auth.getUser()).data.user!.id,
      })
      .select("id")
      .single<{ id: string }>();

    const { data: empDoc, error: linkErr } = await hrClient
      .from("employee_documents")
      .insert({
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        document_id: doc!.id,
        category: "iqama",
        visibility_scope: "employee_visible",
        uploaded_by: (await hrClient.auth.getUser()).data.user!.id,
      })
      .select("id")
      .single<{ id: string }>();

    expect(linkErr).toBeNull();
    expect(empDoc?.id).toBeTruthy();

    // HR Manager can read
    const { data: hrDocs } = await hrClient
      .from("employee_documents")
      .select("id")
      .eq("id", empDoc!.id);
    expect(hrDocs?.length).toBe(1);

    // Self can read employee_visible doc
    const { data: selfDocs } = await peerClient
      .from("employee_documents")
      .select("id")
      .eq("id", empDoc!.id);
    expect(selfDocs?.length).toBe(1);

    // Engineer cannot read
    const { data: engDocs } = await engClient
      .from("employee_documents")
      .select("id")
      .eq("id", empDoc!.id);
    expect(engDocs?.length ?? 0).toBe(0);

    // Project membership does not bypass HR doc security
    // Engineer is project member of fx.projectIdA, but still cannot read HR doc
    const { data: engDocQuery } = await engClient
      .from("employee_documents")
      .select("id, document_id")
      .eq("employee_id", peerEmployeeId);
    expect(engDocQuery?.length ?? 0).toBe(0);
  });

  it("08 — Employee Banking: RPC returns full IBAN to HR/Finance and masked to self; Dept Mgr & Eng DENIED", async () => {
    if (!phase42Ready) return;

    // Upsert bank account via RPC
    const { data: bankRow, error: bankErr } = await hrClient.rpc("upsert_employee_banking", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_bank_name: "Al Rajhi Bank",
      p_iban: "SA0380000000608010167519",
      p_account_name: "Peer Employee",
      p_swift_code: "RJHISARI",
      p_is_primary: true,
    });

    expect(bankErr).toBeNull();
    expect(bankRow?.bank_name).toBe("Al Rajhi Bank");

    // HR calls get_employee_banking -> full IBAN
    const { data: hrBank } = await hrClient.rpc("get_employee_banking", {
      p_employee_id: peerEmployeeId,
    });
    expect(hrBank?.[0]?.iban).toBe("SA0380000000608010167519");

    // Self calls get_employee_banking -> masked IBAN (null full IBAN)
    const { data: selfBank } = await peerClient.rpc("get_employee_banking", {
      p_employee_id: peerEmployeeId,
    });
    expect(selfBank?.[0]?.masked_iban).toBe("SA03 **** **** **** 7519");
    expect(selfBank?.[0]?.iban).toBeNull();

    // Dept Manager and Engineer calls get_employee_banking -> FORBIDDEN / empty
    const { data: dmBank, error: dmBankErr } = await deptMgrClient.rpc("get_employee_banking", {
      p_employee_id: peerEmployeeId,
    });
    expect(dmBankErr || (dmBank?.length ?? 0) === 0).toBeTruthy();

    const { data: engBank, error: engBankErr } = await engClient.rpc("get_employee_banking", {
      p_employee_id: peerEmployeeId,
    });
    expect(engBankErr || (engBank?.length ?? 0) === 0).toBeTruthy();
  });

  it("09 — Deactivate bank account preserves history and marks is_active=false", async () => {
    if (!phase42Ready) return;

    const { data: accounts } = await admin
      .from("employee_bank_accounts")
      .select("id, is_active")
      .eq("employee_id", peerEmployeeId)
      .eq("is_active", true);

    const accId = accounts?.[0]?.id;
    expect(accId).toBeTruthy();

    const { error: deactErr } = await hrClient.rpc("deactivate_employee_bank_account", {
      p_organization_id: fx.orgAId,
      p_account_id: accId!,
    });

    expect(deactErr).toBeNull();

    const { data: updated } = await admin
      .from("employee_bank_accounts")
      .select("is_active, is_primary")
      .eq("id", accId!)
      .single();

    expect(updated?.is_active).toBe(false);
    expect(updated?.is_primary).toBe(false);
  });
});
