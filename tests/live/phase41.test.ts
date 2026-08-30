import "../setup-env";
import { describe, expect, it, beforeAll, afterAll } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { EMPLOYEE_DIRECTORY_COLUMNS } from "@/lib/hr/labels";
import {
  adminClient,
  liveTestConfigured,
  provisionLiveFixture,
  signInAs,
  type LiveFixture,
} from "./helpers";

const configured = liveTestConfigured();

describe.skipIf(!configured)("live Phase 4.1 employee master & org structure", () => {
  let fx: LiveFixture;
  let phase41Ready = false;
  let admin: SupabaseClient;
  let hrClient: SupabaseClient;
  let engClient: SupabaseClient;
  let peerClient: SupabaseClient;
  let deptMgrClient: SupabaseClient;

  let hrEmail = "";
  let hrPassword = "";
  let peerEmail = "";
  let peerPassword = "";
  let deptMgrUserId = "";
  let deptMgrEmail = "";
  let deptMgrPassword = "";

  let hrEmployeeId = "";
  let peerEmployeeId = "";
  let engEmployeeId = "";
  let deptMgrEmployeeId = "";
  let deptId = "";
  let childDeptId = "";

  beforeAll(async () => {
    fx = await provisionLiveFixture();
    admin = adminClient();

    const { error: colErr } = await admin
      .from("employees")
      .select("id, date_of_birth, gender, employment_type")
      .limit(1);
    const { error: rpcErr } = await admin.rpc("department_would_create_cycle", {
      p_department_id: null,
      p_parent_department_id: null,
    });
    const { data: perm } = await admin
      .from("permissions")
      .select("key")
      .eq("key", "employee.create")
      .maybeSingle();

    phase41Ready =
      !colErr &&
      !(rpcErr?.message ?? "").match(/could not find|does not exist|schema cache/i) &&
      Boolean(perm?.key);

    if (!phase41Ready) {
      console.warn(
        "[live-test] Apply migration 052 (supabase/phase4_fix_052.sql) then re-run phase41 tests.",
      );
      return;
    }

    const prefix = process.env.LIVE_TEST_PASSWORD_PREFIX ?? "MtTest1!";
    hrEmail = `mt-live-hr-${fx.runId}@test.local`;
    hrPassword = `${prefix}hr`;
    peerEmail = `mt-live-peer-${fx.runId}@test.local`;
    peerPassword = `${prefix}peer`;
    deptMgrEmail = `mt-live-dm-${fx.runId}@test.local`;
    deptMgrPassword = `${prefix}dm`;

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
            employee_number: `E${fx.runId}${roleCode.slice(0, 3)}`,
          },
          { onConflict: "organization_id,profile_id" },
        )
        .select("id")
        .single();
      if (empErr || !emp) throw new Error(`employee ${email}: ${empErr?.message}`);
      if (roleCode) {
        const { data: role } = await admin
          .from("roles")
          .select("id")
          .eq("code", roleCode)
          .is("organization_id", null)
          .single();
        if (!role) throw new Error(`role ${roleCode} missing`);
        await admin.from("user_roles").upsert({
          organization_id: fx.orgAId,
          profile_id: userId,
          role_id: role.id,
          scope_type: "organization",
        });
      }
      return { userId, employeeId: emp.id as string };
    }

    ({ employeeId: hrEmployeeId } = await createWithRole(hrEmail, hrPassword, "hr_manager"));
    ({ employeeId: peerEmployeeId } = await createWithRole(peerEmail, peerPassword, "engineer"));
    ({ userId: deptMgrUserId, employeeId: deptMgrEmployeeId } = await createWithRole(
      deptMgrEmail,
      deptMgrPassword,
      "department_manager",
    ));
    void hrEmployeeId;
    void deptMgrEmployeeId;

    const { data: engEmp } = await admin
      .from("employees")
      .select("id")
      .eq("profile_id", fx.users.engineer.id)
      .eq("organization_id", fx.orgAId)
      .maybeSingle();
    if (!engEmp?.id) throw new Error("engineer employee missing from live fixture");
    engEmployeeId = engEmp.id;

    hrClient = await signInAs(hrEmail, hrPassword);
    engClient = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    peerClient = await signInAs(peerEmail, peerPassword);
    deptMgrClient = await signInAs(deptMgrEmail, deptMgrPassword);

    // Department + assignment for manager scope tests
    const { data: dept, error: deptErr } = await hrClient.rpc("upsert_department", {
      p_organization_id: fx.orgAId,
      p_department_id: null,
      p_code: `HR-${fx.runId}`,
      p_name_ar: `إدارة ${fx.runId}`,
      p_name_en: `Dept ${fx.runId}`,
      p_description: null,
      p_parent_department_id: null,
      p_manager_user_id: deptMgrUserId,
      p_is_active: true,
    });
    if (deptErr || !dept) throw new Error(`upsert_department: ${deptErr?.message}`);
    deptId = dept.id;

    await admin.from("employee_departments").upsert(
      {
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        department_id: deptId,
        is_primary: true,
      },
      { onConflict: "employee_id,department_id" },
    );

    // Seed compensation for peer — must stay invisible to dept mgr / engineer
    await admin.from("employee_compensation").upsert(
      {
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        basic_salary: 12000,
        currency: "SAR",
      },
      { onConflict: "employee_id" },
    );

    // Seed compliance for peer
    await admin.from("employee_compliance").upsert(
      {
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        iqama_number: `IQ-${fx.runId}`,
        iqama_expiry: "2027-06-01",
        passport_number: `PP-${fx.runId}`,
        gosi_number: `GOSI-${fx.runId}`,
      },
      { onConflict: "employee_id" },
    );

    // Compliance for engineer (self-read target)
    await admin.from("employee_compliance").upsert(
      {
        organization_id: fx.orgAId,
        employee_id: engEmployeeId,
        iqama_number: `IQ-ENG-${fx.runId}`,
        iqama_expiry: "2027-01-01",
      },
      { onConflict: "employee_id" },
    );
  }, 180_000);

  afterAll(async () => {
    if (!fx) return;
    for (const email of [hrEmail, peerEmail, deptMgrEmail]) {
      if (!email) continue;
      const { data: listed } = await adminClient().auth.admin.listUsers({ perPage: 1000 });
      const match = listed?.users.find((u) => u.email === email);
      if (match) await adminClient().auth.admin.deleteUser(match.id);
    }
    await fx.cleanup();
  });

  it("schema additions exist (052)", () => {
    if (!phase41Ready) {
      expect.fail("Migration 052 not applied — run supabase/phase4_fix_052.sql");
    }
    expect(EMPLOYEE_DIRECTORY_COLUMNS).not.toMatch(/salary|compensation|bank|iqama/i);
  });

  it("HR Manager can read/manage employee master in same org", async () => {
    if (!phase41Ready) return;
    const { data, error } = await hrClient
      .from("employees")
      .select("id, employment_type, date_of_birth, gender")
      .eq("id", peerEmployeeId)
      .maybeSingle();
    expect(error).toBeNull();
    expect(data?.id).toBe(peerEmployeeId);

    const { error: updErr } = await hrClient
      .from("employees")
      .update({
        employment_type: "permanent",
        job_title_ar: `مسمى ${fx.runId}`,
        probation_end: "2026-12-31",
      })
      .eq("id", peerEmployeeId)
      .eq("organization_id", fx.orgAId);
    expect(updErr).toBeNull();
  });

  it("employee can read own record; peer confidential denial", async () => {
    if (!phase41Ready) return;
    const { data: own } = await engClient
      .from("employees")
      .select("id, profile_id")
      .eq("id", engEmployeeId)
      .maybeSingle();
    expect(own?.id).toBe(engEmployeeId);

    const { data: peer } = await engClient
      .from("employees")
      .select("id")
      .eq("id", peerEmployeeId)
      .maybeSingle();
    expect(peer).toBeNull();
  });

  it("employee can read own compliance; peer compliance denied", async () => {
    if (!phase41Ready) return;
    const { data: ownComp } = await engClient
      .from("employee_compliance")
      .select("id, iqama_number")
      .eq("employee_id", engEmployeeId)
      .maybeSingle();
    expect(ownComp?.iqama_number).toContain("IQ-ENG");

    const { data: peerComp } = await engClient
      .from("employee_compliance")
      .select("id, iqama_number")
      .eq("employee_id", peerEmployeeId)
      .maybeSingle();
    expect(peerComp).toBeNull();
  });

  it("HR Manager can manage compliance in same org", async () => {
    if (!phase41Ready) return;
    const { error } = await hrClient.from("employee_compliance").upsert(
      {
        organization_id: fx.orgAId,
        employee_id: peerEmployeeId,
        iqama_number: `IQ-HR-${fx.runId}`,
        passport_expiry: "2028-01-15",
      },
      { onConflict: "employee_id" },
    );
    expect(error).toBeNull();

    const { error: syncErr } = await hrClient.rpc("sync_employee_hr_alert_hooks", {
      p_employee_id: peerEmployeeId,
    });
    expect(syncErr).toBeNull();

    const { data: hooks } = await hrClient
      .from("hr_alert_hooks")
      .select("alert_type, status")
      .eq("employee_id", peerEmployeeId)
      .eq("alert_type", "iqama_expiry");
    expect((hooks ?? []).length).toBeGreaterThanOrEqual(1);
  });

  it("cross-org employee access blocked", async () => {
    if (!phase41Ready) return;
    const { data: orgBEmp, error: insErr } = await admin
      .from("employees")
      .insert({
        organization_id: fx.orgBId,
        profile_id: fx.users.admin.id,
        employment_status: "active",
        is_active: true,
        employee_number: `B-${fx.runId}`,
      })
      .select("id")
      .single();
    // admin profile may already be in org A only — use a dedicated org B user if insert fails uniqueness
    let targetId = orgBEmp?.id;
    if (insErr || !orgBEmp) {
      const { data: listed } = await admin.from("employees").select("id").eq("organization_id", fx.orgBId).limit(1);
      targetId = listed?.[0]?.id;
      if (!targetId) {
        // create orgB-only user
        const email = `mt-live-orgb-${fx.runId}@test.local`;
        const { data: created } = await admin.auth.admin.createUser({
          email,
          password: "MtTest1!orgb",
          email_confirm: true,
          user_metadata: { full_name_ar: "B", full_name_en: "B", locale: "ar" },
        });
        if (created?.user) {
          await admin.from("organization_members").insert({
            organization_id: fx.orgBId,
            profile_id: created.user.id,
            status: "active",
          });
          const { data: e } = await admin
            .from("employees")
            .insert({
              organization_id: fx.orgBId,
              profile_id: created.user.id,
              employment_status: "active",
              is_active: true,
            })
            .select("id")
            .single();
          targetId = e?.id;
        }
      }
    }
    expect(targetId).toBeTruthy();

    const { data: stolen } = await hrClient
      .from("employees")
      .select("id")
      .eq("id", targetId!)
      .maybeSingle();
    expect(stolen).toBeNull();
  });

  it("engineer cannot enumerate confidential employee/compliance records", async () => {
    if (!phase41Ready) return;
    const { data: emps } = await engClient
      .from("employees")
      .select("id")
      .eq("organization_id", fx.orgAId);
    const ids = (emps ?? []).map((e) => e.id);
    expect(ids.every((id) => id === engEmployeeId)).toBe(true);

    const { data: comps } = await engClient
      .from("employee_compliance")
      .select("employee_id, iqama_number")
      .eq("organization_id", fx.orgAId);
    expect((comps ?? []).every((c) => c.employee_id === engEmployeeId)).toBe(true);
  });

  it("department hierarchy validation rejects cycles", async () => {
    if (!phase41Ready) return;
    const { data: child, error: childErr } = await hrClient.rpc("upsert_department", {
      p_organization_id: fx.orgAId,
      p_department_id: null,
      p_code: `CH-${fx.runId}`,
      p_name_ar: `فرع ${fx.runId}`,
      p_name_en: `Child ${fx.runId}`,
      p_description: null,
      p_parent_department_id: deptId,
      p_manager_user_id: null,
      p_is_active: true,
    });
    expect(childErr).toBeNull();
    childDeptId = child.id;

    const { data: cycleFlag } = await hrClient.rpc("department_would_create_cycle", {
      p_department_id: deptId,
      p_parent_department_id: childDeptId,
    });
    expect(cycleFlag).toBe(true);

    const { error: cycleErr } = await hrClient.rpc("upsert_department", {
      p_organization_id: fx.orgAId,
      p_department_id: deptId,
      p_code: `HR-${fx.runId}`,
      p_name_ar: `إدارة ${fx.runId}`,
      p_name_en: `Dept ${fx.runId}`,
      p_description: null,
      p_parent_department_id: childDeptId,
      p_manager_user_id: deptMgrUserId,
      p_is_active: true,
    });
    expect(cycleErr?.message ?? "").toMatch(/CYCLE|cycle|FORBIDDEN|P0001/i);
  });

  it("employee directory projection does not expose compensation", async () => {
    if (!phase41Ready) return;
    expect(EMPLOYEE_DIRECTORY_COLUMNS).not.toMatch(/salary|allowance|compensation|bank/i);

    const { data: comp } = await deptMgrClient
      .from("employee_compensation")
      .select("basic_salary")
      .eq("employee_id", peerEmployeeId)
      .maybeSingle();
    expect(comp).toBeNull();

    // Dept manager can read managed employee operational row
    const { data: managed } = await deptMgrClient
      .from("employees")
      .select("id, job_title_ar")
      .eq("id", peerEmployeeId)
      .maybeSingle();
    expect(managed?.id).toBe(peerEmployeeId);

    // But not peer compliance
    const { data: mgrComp } = await deptMgrClient
      .from("employee_compliance")
      .select("iqama_number")
      .eq("employee_id", peerEmployeeId)
      .maybeSingle();
    expect(mgrComp).toBeNull();
  });

  it("deactivation preserves history (no hard delete)", async () => {
    if (!phase41Ready) return;
    const { error } = await hrClient
      .from("employees")
      .update({ is_active: false, employment_status: "terminated", terminated_at: new Date().toISOString() })
      .eq("id", peerEmployeeId)
      .eq("organization_id", fx.orgAId);
    expect(error).toBeNull();

    const { data: still } = await hrClient
      .from("employees")
      .select("id, is_active")
      .eq("id", peerEmployeeId)
      .maybeSingle();
    expect(still?.id).toBe(peerEmployeeId);
    expect(still?.is_active).toBe(false);

    const { data: deleted, error: delErr } = await hrClient
      .from("employees")
      .delete()
      .eq("id", peerEmployeeId)
      .select("id");
    expect(delErr).toBeNull();
    expect(deleted ?? []).toEqual([]);

    // reactivate for cleanup friendliness
    await hrClient
      .from("employees")
      .update({ is_active: true, employment_status: "active", terminated_at: null })
      .eq("id", peerEmployeeId);
  });

  it("peer employee cannot read another employee compliance", async () => {
    if (!phase41Ready) return;
    const { data } = await peerClient
      .from("employee_compliance")
      .select("id")
      .eq("employee_id", engEmployeeId)
      .maybeSingle();
    expect(data).toBeNull();
  });
});
