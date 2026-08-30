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

describe.skipIf(!configured)("Focused Migration 054 Remote Verification", () => {
  let fx: LiveFixture;
  let admin: SupabaseClient;
  let hrClient: SupabaseClient;
  let finClient: SupabaseClient;
  let peerClient: SupabaseClient;
  let deptMgrClient: SupabaseClient;
  let engClient: SupabaseClient;
  let crossClient: SupabaseClient;

  let hrEmployeeId = "";
  let peerEmployeeId = "";

  beforeAll(async () => {
    admin = adminClient();
    fx = await provisionLiveFixture();

    const prefix = process.env.LIVE_TEST_PASSWORD_PREFIX ?? "MtTest1!";
    const hrEmail = `mt-v054-hr-${fx.runId}@test.local`;
    const hrPassword = `${prefix}hr54`;
    const finEmail = `mt-v054-fin-${fx.runId}@test.local`;
    const finPassword = `${prefix}fin54`;
    const peerEmail = `mt-v054-peer-${fx.runId}@test.local`;
    const peerPassword = `${prefix}peer54`;
    const dmEmail = `mt-v054-dm-${fx.runId}@test.local`;
    const dmPassword = `${prefix}dm54`;

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
            employee_number: `E54${fx.runId}${crypto.randomUUID().slice(0, 6)}`,
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
    crossClient = await signInAs(fx.users.restricted.email, fx.users.restricted.password);
  }, 120_000);

  afterAll(async () => {
    if (fx?.cleanup) await fx.cleanup();
  }, 120_000);

  // ==========================================
  // SECTION A: VERSIONED COMPENSATION BASICS & RBAC/RLS
  // ==========================================

  it("A.1 - employee_compensation_versions exists and RLS enabled", async () => {
    const { error } = await admin.from("employee_compensation_versions").select("id").limit(1);
    expect(error).toBeNull();

    // Cross-org / anonymous gets 0 rows
    const { data: crossRows } = await crossClient
      .from("employee_compensation_versions")
      .select("id")
      .eq("organization_id", fx.orgAId);
    expect(crossRows?.length ?? 0).toBe(0);
  });

  it("A.2 - permissions and role grants are correctly assigned", async () => {
    const { data: perms } = await admin
      .from("permissions")
      .select("key")
      .in("key", ["employee_compensation.read", "employee_compensation.manage"]);
    expect(perms?.map((p) => p.key)).toEqual(
      expect.arrayContaining(["employee_compensation.read", "employee_compensation.manage"]),
    );

    // HR Manager grants
    const { data: hrRole } = await admin.from("roles").select("id").eq("code", "hr_manager").is("organization_id", null).single();
    const { data: hrGrants } = await admin.from("role_permissions").select("permission_key").eq("role_id", hrRole!.id);
    const hrKeys = hrGrants?.map((g) => g.permission_key) ?? [];
    expect(hrKeys).toContain("employee_compensation.read");
    expect(hrKeys).toContain("employee_compensation.manage");

    // Finance Manager grants
    const { data: finRole } = await admin.from("roles").select("id").eq("code", "finance_manager").is("organization_id", null).single();
    const { data: finGrants } = await admin.from("role_permissions").select("permission_key").eq("role_id", finRole!.id);
    const finKeys = finGrants?.map((g) => g.permission_key) ?? [];
    expect(finKeys).toContain("employee_compensation.read");
    expect(finKeys).not.toContain("employee_compensation.manage"); // Read only, no HR manage
  });

  it("A.3 - Department Manager, Engineer, and Peer are DENIED direct compensation access", async () => {
    const { data: dmComp } = await deptMgrClient.from("employee_compensation_versions").select("id").eq("employee_id", peerEmployeeId);
    expect(dmComp?.length ?? 0).toBe(0);

    const { data: engComp } = await engClient.from("employee_compensation_versions").select("id").eq("employee_id", peerEmployeeId);
    expect(engComp?.length ?? 0).toBe(0);

    const { data: peerComp } = await peerClient.from("employee_compensation_versions").select("id").eq("employee_id", hrEmployeeId);
    expect(peerComp?.length ?? 0).toBe(0);
  });

  // ==========================================
  // SECTION B: LEGACY BACKFILL AUDIT
  // ==========================================

  it("B.1 - legacy backfill audit", async () => {
    // 1. Check legacy rows
    const { data: legacyRows, error: lErr } = await admin.from("employee_compensation").select("id, employee_id, basic_salary, currency");
    expect(lErr).toBeNull();
    const totalLegacy = legacyRows?.length ?? 0;
    const legacyWithSalary = legacyRows?.filter((r) => r.basic_salary && r.basic_salary > 0) ?? [];
    expect(totalLegacy).toBeGreaterThanOrEqual(0);
    expect(legacyWithSalary.length).toBe(totalLegacy);

    // 2. Check version rows
    const { data: versionRows, error: vErr } = await admin.from("employee_compensation_versions").select("id, employee_id, basic_salary, currency, status, change_reason, effective_from");
    expect(vErr).toBeNull();
    const totalVersions = versionRows?.length ?? 0;
    expect(totalVersions).toBeGreaterThanOrEqual(totalLegacy);

    // Check for duplicate backfilled versions per employee
    const backfilled = versionRows?.filter((v) => v.change_reason?.includes("backfill")) ?? [];
    const empIds = backfilled.map((b) => b.employee_id);
    const uniqueEmpIds = new Set(empIds);
    expect(empIds.length).toBe(uniqueEmpIds.size); // No duplicates

    // Verify no zero/null salary rows were fabricated as backfills
    for (const b of backfilled) {
      expect(Number(b.basic_salary)).toBeGreaterThan(0);
      expect(b.effective_from).toBeTruthy();
    }
  });

  // ==========================================
  // SECTION C: COMPENSATION VERSIONING RULES & CONCURRENCY
  // ==========================================

  it("C.1 - version lifecycle: auto-supersede, status update, date boundary", async () => {
    // 1. Create first version
    const { data: v1, error: e1 } = await hrClient.rpc("create_employee_compensation_version", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_effective_from: "2026-01-01",
      p_currency: "SAR",
      p_basic_salary: 10000,
      p_housing_allowance: 2500,
      p_transport_allowance: 1000,
      p_other_allowances: 0,
      p_change_reason: "Initial package",
    });
    expect(e1).toBeNull();
    expect(v1?.status).toBe("active");
    expect(v1?.effective_to).toBeNull();

    // 2. Create second version effective 2026-07-01
    const { data: v2, error: e2 } = await hrClient.rpc("create_employee_compensation_version", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_effective_from: "2026-07-01",
      p_currency: "SAR",
      p_basic_salary: 12000,
      p_housing_allowance: 3000,
      p_transport_allowance: 1000,
      p_other_allowances: 500,
      p_change_reason: "Annual increase",
    });
    expect(e2).toBeNull();
    expect(v2?.status).toBe("active");

    // Check v1 became superseded with effective_to = 2026-06-30
    const { data: v1Refetched } = await admin.from("employee_compensation_versions").select("status, effective_to").eq("id", v1.id).single();
    expect(v1Refetched?.status).toBe("superseded");
    expect(v1Refetched?.effective_to).toBe("2026-06-30");

    // 3. Validation: negative salary / allowance rejected
    const { error: negSalErr } = await hrClient.rpc("create_employee_compensation_version", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_effective_from: "2026-10-01",
      p_currency: "SAR",
      p_basic_salary: -500,
    });
    expect(negSalErr).toBeTruthy();

    // 4. Immutability: historical superseded version cannot be directly updated
    const { error: modErr } = await hrClient.from("employee_compensation_versions").update({ basic_salary: 99999 }).eq("id", v1.id);
    expect(modErr).toBeTruthy();
    expect(modErr?.message).toMatch(/IMMUTABLE_COMPENSATION/i);
  });

  it("C.2 - concurrency protection: create_employee_compensation_version uses FOR UPDATE locking", async () => {
    // Run two RPC calls in parallel for same employee with different dates
    const [res1, res2] = await Promise.all([
      hrClient.rpc("create_employee_compensation_version", {
        p_organization_id: fx.orgAId,
        p_employee_id: peerEmployeeId,
        p_effective_from: "2027-01-01",
        p_currency: "SAR",
        p_basic_salary: 15000,
        p_change_reason: "Parallel call A",
      }),
      hrClient.rpc("create_employee_compensation_version", {
        p_organization_id: fx.orgAId,
        p_employee_id: peerEmployeeId,
        p_effective_from: "2027-06-01",
        p_currency: "SAR",
        p_basic_salary: 16000,
        p_change_reason: "Parallel call B",
      }),
    ]);

    // Verify database concurrency protection safely resolved or rejected the conflicting parallel attempt
    expect(res1.data || res2.data).toBeTruthy();

    // Check that exactly one active version is open-ended (effective_to is null)
    const { data: openActive } = await admin
      .from("employee_compensation_versions")
      .select("id, effective_from, effective_to, status")
      .eq("employee_id", peerEmployeeId)
      .eq("status", "active")
      .is("effective_to", null);

    expect(openActive?.length).toBe(1);
  });

  // ==========================================
  // SECTION D: DATA LEAKAGE AUDIT
  // ==========================================

  it("D.1 - directory and generic queries do not project compensation columns", async () => {
    const { data: emp } = await admin.from("employees").select("*").eq("id", peerEmployeeId).single();
    expect(emp).not.toHaveProperty("basic_salary");
    expect(emp).not.toHaveProperty("housing_allowance");
    expect(emp).not.toHaveProperty("transport_allowance");
    expect(emp).not.toHaveProperty("compensation");
  });

  // ==========================================
  // SECTION E & F: BANKING BASICS, RPCS, AUTHORIZATION & MASKING
  // ==========================================

  it("E/F.1 - employee_bank_accounts exists, RPCs exist, authorization matrix verified", async () => {
    const { error: bErr } = await admin.from("employee_bank_accounts").select("id").limit(1);
    expect(bErr).toBeNull();

    const testIban = "SA0380000000608010167519";

    // 1. HR Manager creates bank account
    const { data: bank1, error: insErr } = await hrClient.rpc("upsert_employee_banking", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_bank_name: "Al Rajhi Bank",
      p_iban: testIban,
      p_account_name: "Peer Employee Primary",
      p_is_primary: true,
    });
    expect(insErr).toBeNull();
    expect(bank1?.id).toBeTruthy();

    // 2. HR gets full IBAN
    const { data: hrBank } = await hrClient.rpc("get_employee_banking", { p_employee_id: peerEmployeeId });
    expect(hrBank?.[0]?.iban).toBe(testIban);

    // 3. Finance Manager gets full IBAN
    const { data: finBank } = await finClient.rpc("get_employee_banking", { p_employee_id: peerEmployeeId });
    expect(finBank?.[0]?.iban).toBe(testIban);

    // 4. Employee Self gets masked IBAN and NULL full IBAN
    const { data: selfBank } = await peerClient.rpc("get_employee_banking", { p_employee_id: peerEmployeeId });
    expect(selfBank?.[0]?.masked_iban).toBe("SA03 **** **** **** 7519");
    expect(selfBank?.[0]?.iban).toBeNull();

    // 5. Department Manager, Engineer, Peer (non-self) DENIED
    const { data: dmRes, error: dmErr } = await deptMgrClient.rpc("get_employee_banking", { p_employee_id: peerEmployeeId });
    expect(dmErr || (dmRes?.length ?? 0) === 0).toBeTruthy();

    const { data: engRes, error: engErr } = await engClient.rpc("get_employee_banking", { p_employee_id: peerEmployeeId });
    expect(engErr || (engRes?.length ?? 0) === 0).toBeTruthy();

    const { data: peerRes, error: peerErr } = await peerClient.rpc("get_employee_banking", { p_employee_id: hrEmployeeId });
    expect(peerErr || (peerRes?.length ?? 0) === 0).toBeTruthy();

    const { data: crossRes, error: crossErr } = await crossClient.rpc("get_employee_banking", { p_employee_id: peerEmployeeId });
    expect(crossErr || (crossRes?.length ?? 0) === 0).toBeTruthy();
  });

  // ==========================================
  // SECTION H: BANKING STATE RULES & PRIMARY UNIQUENESS
  // ==========================================

  it("H.1 - primary switching, deactivation, history preservation", async () => {
    // Add second account as primary
    const { data: bank2, error: e2 } = await hrClient.rpc("upsert_employee_banking", {
      p_organization_id: fx.orgAId,
      p_employee_id: peerEmployeeId,
      p_bank_name: "SNB AlAhli",
      p_iban: "SA5510000000123456789012",
      p_account_name: "Peer Employee Secondary",
      p_is_primary: true,
    });
    expect(e2).toBeNull();

    // Verify only bank2 is primary; previous account became non-primary
    const { data: accounts } = await admin
      .from("employee_bank_accounts")
      .select("id, bank_name, is_primary, is_active")
      .eq("employee_id", peerEmployeeId)
      .eq("is_active", true);

    const primaryAccounts = accounts?.filter((a) => a.is_primary) ?? [];
    expect(primaryAccounts.length).toBe(1);
    expect(primaryAccounts[0].id).toBe(bank2.id);

    // Deactivate primary account
    const { error: deactErr } = await hrClient.rpc("deactivate_employee_bank_account", {
      p_organization_id: fx.orgAId,
      p_account_id: bank2.id,
    });
    expect(deactErr).toBeNull();

    // Verify record is preserved, is_active=false, is_primary=false
    const { data: deactAcc } = await admin.from("employee_bank_accounts").select("is_active, is_primary").eq("id", bank2.id).single();
    expect(deactAcc?.is_active).toBe(false);
    expect(deactAcc?.is_primary).toBe(false);
  });

  it("H.2 - concurrent bank account creation setting primary leaves at most 1 active primary", async () => {
    // Run two parallel calls setting primary = true
    await Promise.all([
      hrClient.rpc("upsert_employee_banking", {
        p_organization_id: fx.orgAId,
        p_employee_id: peerEmployeeId,
        p_bank_name: "Riyad Bank A",
        p_iban: "SA4420000000987654321098",
        p_account_name: "Concurrent A",
        p_is_primary: true,
      }),
      hrClient.rpc("upsert_employee_banking", {
        p_organization_id: fx.orgAId,
        p_employee_id: peerEmployeeId,
        p_bank_name: "Riyad Bank B",
        p_iban: "SA7730000000112233445566",
        p_account_name: "Concurrent B",
        p_is_primary: true,
      }),
    ]);

    const { data: activeAccounts } = await admin
      .from("employee_bank_accounts")
      .select("id, is_primary, is_active")
      .eq("employee_id", peerEmployeeId)
      .eq("is_active", true);

    const activePrimaries = activeAccounts?.filter((a) => a.is_primary) ?? [];
    expect(activePrimaries.length).toBeLessThanOrEqual(1);
  });

  // ==========================================
  // SECTION I: AUDIT SANITIZATION
  // ==========================================

  it("I.1 - audit metadata does not contain raw salary or full IBAN", async () => {
    const { data: logs } = await admin
      .from("audit_logs")
      .select("action, new_values")
      .eq("organization_id", fx.orgAId)
      .in("action", ["employee_compensation.changed", "employee_bank.updated", "employee_bank.deactivated"]);

    expect(logs?.length).toBeGreaterThan(0);
    for (const log of logs ?? []) {
      const serialized = JSON.stringify(log.new_values ?? {});
      expect(serialized).not.toMatch(/basic_salary|housing_allowance|allowance/i);
      expect(serialized).not.toMatch(/SA0380000000608010167519|SA5510000000123456789012/i);
    }
  });
});
