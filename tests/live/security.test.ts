import { describe, expect, it, beforeAll, afterAll } from "vitest";
import {
  adminClient,
  liveTestConfigured,
  provisionLiveFixture,
  skipLive,
  verifySchema,
  type LiveFixture,
} from "./helpers";

const configured = liveTestConfigured();

describe.skipIf(!configured)("live schema verification", () => {
  it("all Phase 1 tables and private storage bucket exist", async () => {
    const admin = adminClient();
    const report = await verifySchema(admin);
    const missing = report.tables.filter((t) => !t.ok);
    expect(missing, JSON.stringify(missing, null, 2)).toEqual([]);
    expect(report.bucketPrivate).toBe(true);
  });
});

describe.skipIf(!configured)("live security & functional matrix", () => {
  let fx: LiveFixture;

  beforeAll(async () => {
    fx = await provisionLiveFixture();
  }, 120_000);

  afterAll(async () => {
    if (fx) await fx.cleanup();
  }, 60_000);

  it("unauthenticated client cannot read projects", async () => {
    const { anonClient } = await import("./helpers");
    const anon = anonClient();
    const { data, error } = await anon.from("projects").select("id").limit(1);
    expect(data ?? []).toEqual([]);
    expect(error).toBeTruthy();
  });

  it("org A user cannot read org B project by id", async () => {
    const { signInAs } = await import("./helpers");
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);
    const { data } = await pm.from("projects").select("id").eq("id", fx.orgBProjectId).maybeSingle();
    expect(data).toBeNull();
  });

  it("restricted user cannot read org A project without membership", async () => {
    const { signInAs } = await import("./helpers");
    const restricted = await signInAs(fx.users.restricted.email, fx.users.restricted.password);
    const { data } = await restricted.from("projects").select("id").eq("id", fx.projectId).maybeSingle();
    expect(data).toBeNull();
  });

  it("engineer can read project when assigned as member", async () => {
    const { signInAs, adminClient } = await import("./helpers");
    const admin = adminClient();
    await admin.from("project_members").upsert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      profile_id: fx.users.engineer.id,
      role_label: "engineer",
      is_active: true,
    });
    const eng = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    const { data, error } = await eng.from("projects").select("id").eq("id", fx.projectId).maybeSingle();
    expect(error).toBeNull();
    expect(data?.id).toBe(fx.projectId);
  });

  it("project codes are unique under concurrent creation", async () => {
    const { signInAs } = await import("./helpers");
    const admin = await signInAs(fx.users.admin.email, fx.users.admin.password);
    const results = await Promise.all(
      Array.from({ length: 5 }).map(() =>
        admin.rpc("create_project", {
          p_organization_id: fx.orgAId,
          p_name_ar: "تزامن",
          p_name_en: "Concurrent",
          p_description: null,
          p_client_id: null,
          p_project_manager_id: null,
          p_priority: "medium",
          p_start_date: null,
          p_planned_end_date: null,
          p_location: null,
          p_template_id: null,
        }),
      ),
    );
    const codes = results.map((r) => (r.data as { project_code: string })?.project_code).filter(Boolean);
    expect(new Set(codes).size).toBe(codes.length);
    for (const code of codes) {
      expect(code).toMatch(/^MT-PRJ-\d{4}$/);
    }
  });

  it("approval A–E: only assigned approver can decide", async () => {
    const { signInAs } = await import("./helpers");
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);

    const { data: request } = await pm
      .from("approval_requests")
      .insert({
        organization_id: fx.orgAId,
        entity_type: "project",
        entity_id: fx.projectId,
        title: "Live approval",
        status: "in_progress",
        mode: "sequential",
        requested_by: fx.users.pm.id,
        due_at: new Date(Date.now() + 86_400_000).toISOString(),
      })
      .select("id")
      .single();

    const { data: step } = await pm
      .from("approval_steps")
      .insert({
        organization_id: fx.orgAId,
        request_id: request!.id,
        sequence: 1,
        approver_type: "user",
        user_id: fx.users.pm.id,
        status: "in_progress",
      })
      .select("id")
      .single();

    const engineer = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    const denied = await engineer.rpc("submit_approval_decision", {
      p_step_id: step!.id,
      p_official_code: "A",
      p_comment: "should fail",
    });
    expect(denied.error?.message).toMatch(/FORBIDDEN/i);

    const allowed = await pm.rpc("submit_approval_decision", {
      p_step_id: step!.id,
      p_official_code: "A",
      p_comment: "approved live",
    });
    expect(allowed.error).toBeNull();
    expect(allowed.data?.official_code).toBe("A");

    const duplicate = await pm.rpc("submit_approval_decision", {
      p_step_id: step!.id,
      p_official_code: "B",
      p_comment: "duplicate",
    });
    expect(duplicate.error?.message).toMatch(/CONFLICT/i);
  });

  it("SLA queries detect overdue approvals", async () => {
    const { signInAs } = await import("./helpers");
    const admin = await signInAs(fx.users.admin.email, fx.users.admin.password);
    const past = new Date(Date.now() - 86_400_000).toISOString();
    const future = new Date(Date.now() + 86_400_000).toISOString();

    await admin.from("approval_requests").insert([
      {
        organization_id: fx.orgAId,
        entity_type: "project",
        entity_id: fx.projectId,
        title: "Overdue",
        status: "in_progress",
        requested_by: fx.users.admin.id,
        due_at: past,
      },
      {
        organization_id: fx.orgAId,
        entity_type: "project",
        entity_id: fx.projectId,
        title: "Future",
        status: "in_progress",
        requested_by: fx.users.admin.id,
        due_at: future,
        warning_at: future,
      },
    ]);

    const now = new Date().toISOString();
    const { count: overdue } = await admin
      .from("approval_requests")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", fx.orgAId)
      .in("status", ["pending", "in_progress"])
      .lt("due_at", now);
    expect((overdue ?? 0) >= 1).toBe(true);
  });

  it("notifications are recipient-scoped", async () => {
    const { signInAs, adminClient } = await import("./helpers");
    const admin = adminClient();
    const { data: note } = await admin
      .from("notifications")
      .insert({
        organization_id: fx.orgAId,
        recipient_profile_id: fx.users.pm.id,
        type: "test.live",
        title: "تنبيه",
        message: "live",
        priority: "normal",
      })
      .select("id")
      .single();

    const eng = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    const { data: stolen } = await eng.from("notifications").select("id").eq("id", note!.id).maybeSingle();
    expect(stolen).toBeNull();

    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);
    const { data: owned } = await pm.from("notifications").select("id").eq("id", note!.id).maybeSingle();
    expect(owned?.id).toBe(note!.id);
  });

  it("deactivated employee loses access but history remains", async () => {
    const { signInAs, adminClient } = await import("./helpers");
    const admin = adminClient();
    await admin.from("profiles").update({ is_active: false }).eq("id", fx.users.restricted.id);
    await admin
      .from("organization_members")
      .update({ status: "suspended" })
      .eq("profile_id", fx.users.restricted.id);

    const { data: employeeRow } = await admin
      .from("employees")
      .select("id")
      .eq("profile_id", fx.users.restricted.id)
      .maybeSingle();
    expect(employeeRow?.id).toBeTruthy();

    const restricted = await signInAs(fx.users.restricted.email, fx.users.restricted.password);
    const { data } = await restricted.from("projects").select("id").limit(1);
    expect(data ?? []).toEqual([]);
  });

  it("audit log written on project create and not deletable by normal user", async () => {
    const { signInAs } = await import("./helpers");
    const admin = await signInAs(fx.users.admin.email, fx.users.admin.password);
    const { data: logs } = await admin
      .from("audit_logs")
      .select("action")
      .eq("organization_id", fx.orgAId)
      .eq("action", "project.created")
      .limit(1);
    expect((logs ?? []).length >= 1).toBe(true);

    const { error: delErr } = await admin.from("audit_logs").delete().neq("id", "00000000-0000-0000-0000-000000000000");
    expect(delErr).toBeTruthy();
  });
});

if (!configured) {
  skipLive("Set LIVE_TEST_ENABLED=true and Supabase keys in .env.local to run live tests.");
}
