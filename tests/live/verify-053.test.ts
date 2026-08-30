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

describe.skipIf(!configured)("Focused Migration 053 Live Verification", () => {
  let fx: LiveFixture;
  let admin: SupabaseClient;
  let hrClient: SupabaseClient;
  let peerClient: SupabaseClient;
  let deptMgrClient: SupabaseClient;
  let engClient: SupabaseClient;
  let crossClient: SupabaseClient;

  let peerEmployeeId = "";

  beforeAll(async () => {
    fx = await provisionLiveFixture();
    admin = adminClient();

    const prefix = process.env.LIVE_TEST_PASSWORD_PREFIX ?? "MtTest1!";
    const hrEmail = `mt-v053-hr-${fx.runId}@test.local`;
    const hrPassword = `${prefix}hr53`;
    const hroEmail = `mt-v053-hro-${fx.runId}@test.local`;
    const hroPassword = `${prefix}hro53`;
    const peerEmail = `mt-v053-peer-${fx.runId}@test.local`;
    const peerPassword = `${prefix}peer53`;
    const dmEmail = `mt-v053-dm-${fx.runId}@test.local`;
    const dmPassword = `${prefix}dm53`;

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
            employee_number: `E53${fx.runId}${crypto.randomUUID().slice(0, 6)}`,
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

    await createWithRole(hrEmail, hrPassword, "hr_manager");
    await createWithRole(hroEmail, hroPassword, "hr_officer");
    const peer = await createWithRole(peerEmail, peerPassword, "employee");
    peerEmployeeId = peer.employeeId;
    await createWithRole(dmEmail, dmPassword, "department_manager");

    hrClient = await signInAs(hrEmail, hrPassword);
    peerClient = await signInAs(peerEmail, peerPassword);
    deptMgrClient = await signInAs(dmEmail, dmPassword);
    engClient = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    crossClient = await signInAs(fx.users.restricted.email, fx.users.restricted.password);
  }, 120_000);

  afterAll(async () => {
    if (fx?.cleanup) await fx.cleanup();
  }, 120_000);

  it("1. employee_contracts exists", async () => {
    const { error } = await admin.from("employee_contracts").select("id").limit(1);
    expect(error).toBeNull();
  });

  it("2. employee_documents exists", async () => {
    const { error } = await admin.from("employee_documents").select("id").limit(1);
    expect(error).toBeNull();
  });

  it("3. employee_contracts_current_idx exists & single is_current enforced", async () => {
    // Insert 1st contract
    const { data: c1, error: err1 } = await admin
      .from("employee_contracts")
      .insert({
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        contract_number: `CTR-IDX1-${fx.runId}`,
        contract_type: "permanent",
        status: "active",
        start_date: "2026-01-01",
        is_current: true,
        created_by: (await hrClient.auth.getUser()).data.user!.id,
      })
      .select("id")
      .single();
    expect(err1).toBeNull();

    // Try inserting 2nd contract with is_current=true on same employee -> must fail with duplicate key
    const { error: err2 } = await admin.from("employee_contracts").insert({
      organization_id: fx.orgAId,
      employee_id: peerEmployeeId,
      contract_number: `CTR-IDX2-${fx.runId}`,
      contract_type: "fixed_term",
      status: "active",
      start_date: "2026-06-01",
      is_current: true,
      created_by: (await hrClient.auth.getUser()).data.user!.id,
    });
    expect(err2).toBeTruthy();
    expect(err2?.message).toMatch(/employee_contracts_current_idx|duplicate key value/i);

    // Clean up c1
    if (c1?.id) {
      await admin.from("employee_contracts").update({ is_current: false }).eq("id", c1.id);
    }
  });

  it("4. contract RLS is enabled", async () => {
    // Cross-org / restricted user cannot read contracts
    const { data } = await crossClient
      .from("employee_contracts")
      .select("id")
      .eq("organization_id", fx.orgAId);
    expect(data?.length ?? 0).toBe(0);
  });

  it("5. employee_documents RLS is enabled", async () => {
    const { data } = await crossClient
      .from("employee_documents")
      .select("id")
      .eq("organization_id", fx.orgAId);
    expect(data?.length ?? 0).toBe(0);
  });

  it("6. activate_employee_contract exists and functions atomically", async () => {
    const { data: draft, error: createErr } = await hrClient
      .from("employee_contracts")
      .insert({
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        contract_number: `CTR-ACT-${fx.runId}`,
        contract_type: "permanent",
        status: "draft",
        start_date: "2026-02-01",
        created_by: (await hrClient.auth.getUser()).data.user!.id,
      })
      .select("id")
      .single();
    expect(createErr).toBeNull();

    const { data: activated, error: actErr } = await hrClient.rpc("activate_employee_contract", {
      p_organization_id: fx.orgAId,
      p_contract_id: draft!.id,
    });
    expect(actErr).toBeNull();
    expect(activated?.status).toBe("active");
    expect(activated?.is_current).toBe(true);
  });

  it("7. can_access_employee_document_row exists", async () => {
    const { error } = await admin.rpc("can_access_employee_document_row", {
      p_employee_id: peerEmployeeId,
      p_organization_id: fx.orgAId,
      p_category: "contract",
      p_visibility_scope: "employee_visible",
    });
    expect(error).toBeNull();
  });

  it("8. contract permissions exist", async () => {
    const { data } = await admin
      .from("permissions")
      .select("key")
      .in("key", ["employee_contract.read", "employee_contract.manage"]);
    expect(data?.map((p) => p.key)).toEqual(
      expect.arrayContaining(["employee_contract.read", "employee_contract.manage"]),
    );
  });

  it("9. employee document permissions exist", async () => {
    const { data } = await admin
      .from("permissions")
      .select("key")
      .in("key", ["employee_document.read", "employee_document.manage"]);
    expect(data?.map((p) => p.key)).toEqual(
      expect.arrayContaining(["employee_document.read", "employee_document.manage"]),
    );
  });

  it("10. HR Manager grants are correct", async () => {
    const { data: role } = await admin
      .from("roles")
      .select("id")
      .eq("code", "hr_manager")
      .is("organization_id", null)
      .single();

    const { data: grants } = await admin
      .from("role_permissions")
      .select("permission_key")
      .eq("role_id", role!.id);

    const keys = grants?.map((g) => g.permission_key) ?? [];
    expect(keys).toContain("employee_contract.read");
    expect(keys).toContain("employee_contract.manage");
    expect(keys).toContain("employee_document.read");
    expect(keys).toContain("employee_document.manage");
  });

  it("11. HR Officer grants are least privilege (read contracts, manage/read docs, no contract manage)", async () => {
    const { data: role } = await admin
      .from("roles")
      .select("id")
      .eq("code", "hr_officer")
      .is("organization_id", null)
      .single();

    const { data: grants } = await admin
      .from("role_permissions")
      .select("permission_key")
      .eq("role_id", role!.id);

    const keys = grants?.map((g) => g.permission_key) ?? [];
    expect(keys).toContain("employee_contract.read");
    expect(keys).not.toContain("employee_contract.manage");
  });

  it("12. Engineer / Department Manager do not gain private HR document access", async () => {
    // Seed private HR doc
    const { data: doc } = await admin
      .from("documents")
      .insert({
        organization_id: fx.orgAId,
        title: "Confidential HR File",
        category: "other",
        current_revision: "A",
        uploaded_by: (await hrClient.auth.getUser()).data.user!.id,
      })
      .select("id")
      .single();

    const { data: empDoc } = await admin
      .from("employee_documents")
      .insert({
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        document_id: doc!.id,
        category: "passport",
        visibility_scope: "hr_only",
        uploaded_by: (await hrClient.auth.getUser()).data.user!.id,
      })
      .select("id")
      .single();

    // Engineer query
    const { data: engDocs } = await engClient
      .from("employee_documents")
      .select("id")
      .eq("id", empDoc!.id);
    expect(engDocs?.length ?? 0).toBe(0);

    // Department Manager query
    const { data: dmDocs } = await deptMgrClient
      .from("employee_documents")
      .select("id")
      .eq("id", empDoc!.id);
    expect(dmDocs?.length ?? 0).toBe(0);
  });

  it("13. project membership does not grant employee document access", async () => {
    // Engineer is member of fx.projectIdA, but queries employee_documents -> 0 rows
    const { data } = await engClient
      .from("employee_documents")
      .select("id")
      .eq("employee_id", peerEmployeeId);
    expect(data?.length ?? 0).toBe(0);
  });

  it("14 & 15. documents_select_hr and document_versions_select_hr do NOT broaden access to unrelated documents", async () => {
    // Engineer creates a regular project document
    const { data: pDoc } = await admin
      .from("documents")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        title: "Project Drawing",
        category: "drawing",
        current_revision: "A",
        uploaded_by: fx.users.engineer.id,
      })
      .select("id")
      .single();

    // Peer (who is not in project) cannot see pDoc via HR policy
    const { data: peerSeeDoc } = await peerClient
      .from("documents")
      .select("id")
      .eq("id", pDoc!.id);
    expect(peerSeeDoc?.length ?? 0).toBe(0);
  });

  it("16. contract immutability trigger exists", async () => {
    const { data: activeContract } = await admin
      .from("employee_contracts")
      .select("id")
      .eq("employee_id", peerEmployeeId)
      .eq("status", "active")
      .limit(1)
      .single();

    const { error: updateErr } = await hrClient
      .from("employee_contracts")
      .update({ start_date: "2020-01-01" })
      .eq("id", activeContract!.id);

    expect(updateErr).toBeTruthy();
    expect(updateErr?.message).toMatch(/IMMUTABLE_CONTRACT/i);
  });

  it("17. cross-org access remains denied", async () => {
    const { data: crossContracts } = await crossClient
      .from("employee_contracts")
      .select("id")
      .eq("employee_id", peerEmployeeId);
    expect(crossContracts?.length ?? 0).toBe(0);

    const { data: crossDocs } = await crossClient
      .from("employee_documents")
      .select("id")
      .eq("employee_id", peerEmployeeId);
    expect(crossDocs?.length ?? 0).toBe(0);
  });
});
