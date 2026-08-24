import "../setup-env";
import { describe, expect, it, beforeAll, afterAll } from "vitest";
import {
  adminClient,
  liveTestConfigured,
  provisionLiveFixture,
  signInAs,
  type LiveFixture,
} from "./helpers";

const configured = liveTestConfigured();

describe.skipIf(!configured)("live Phase 2 document control & access", () => {
  let fx: LiveFixture;
  let phase2Ready = false;

  beforeAll(async () => {
    fx = await provisionLiveFixture();
    const admin = adminClient();
    const { error } = await admin.from("engineering_disciplines").select("id").limit(1);
    phase2Ready = !error;
    if (!phase2Ready) {
      console.warn("[live-test] Phase 2 tables missing — apply migrations 015–030 then re-run.");
    }

    await admin.from("engineering_disciplines").upsert(
      {
        organization_id: fx.orgAId,
        code: "GENERAL",
        name_ar: "عام",
        name_en: "General",
        is_active: true,
      },
      { onConflict: "organization_id,code" },
    );

    // Ensure engineer starts without membership for access tests
    await admin
      .from("project_members")
      .update({ is_active: false })
      .eq("project_id", fx.projectId)
      .eq("profile_id", fx.users.engineer.id);
  }, 120_000);

  afterAll(async () => {
    if (fx) await fx.cleanup();
  }, 60_000);

  it("schema has Phase 2 register RPC", async () => {
    if (!phase2Ready) return;
    const admin = adminClient();
    const { error } = await admin.rpc("generate_document_number", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "RFI",
      p_discipline_code: "ELEC",
    });
    expect(error?.message ?? "").not.toMatch(/Could not find the function/i);
  });

  it("concurrent document numbering is unique", async () => {
    if (!phase2Ready) return;
    const admin = adminClient();
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        pm.rpc("register_controlled_document", {
          p_organization_id: fx.orgAId,
          p_project_id: fx.projectId,
          p_type_code: "RFI",
          p_discipline_code: "GENERAL",
          p_title: `Concurrent RFI ${Date.now()}`,
          p_description: "live concurrency test",
          p_responsible_engineer_id: fx.users.pm.id,
          p_confidentiality: "internal",
        }),
      ),
    );

    const numbers = results
      .map((r) => r.data?.document_number as string | undefined)
      .filter(Boolean) as string[];
    const errors = results.filter((r) => r.error).map((r) => r.error?.message);

    expect(errors, JSON.stringify(errors)).toEqual([]);
    expect(numbers.length).toBe(5);
    expect(new Set(numbers).size).toBe(5);

    for (const r of results) {
      if (r.data?.id) {
        await admin.from("rfis").delete().eq("document_id", r.data.id);
        await admin.from("document_versions").delete().eq("document_id", r.data.id);
        await admin.from("documents").delete().eq("id", r.data.id);
      }
    }
  });

  it("revision creates new current and supersedes previous", async () => {
    if (!phase2Ready) return;
    const admin = adminClient();
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);

    const { data: doc, error } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "MAT",
      p_discipline_code: "GENERAL",
      p_title: "Live MAT revision test",
      p_confidentiality: "internal",
    });
    expect(error).toBeNull();
    expect(doc?.current_revision).toBe("R00");

    const { data: revised, error: revErr } = await pm.rpc("create_document_revision", {
      p_document_id: doc.id,
      p_change_description: "Resubmit after C",
    });
    expect(revErr).toBeNull();
    expect(revised?.current_revision).toBe("R01");

    const { data: versions } = await admin
      .from("document_versions")
      .select("revision, is_current, is_superseded")
      .eq("document_id", doc.id)
      .order("revision");

    expect(versions?.length).toBeGreaterThanOrEqual(2);
    const current = versions?.filter((v) => v.is_current);
    const superseded = versions?.filter((v) => v.is_superseded);
    expect(current?.length).toBe(1);
    expect(current?.[0]?.revision).toBe("R01");
    expect(superseded?.some((v) => v.revision === "R00")).toBe(true);

    await admin.from("document_versions").delete().eq("document_id", doc.id);
    await admin.from("documents").delete().eq("id", doc.id);
  });

  it("org management (super_admin) retains organization-wide project access", async () => {
    if (!phase2Ready) return;
    const adminUser = await signInAs(fx.users.admin.email, fx.users.admin.password);
    const { data, error } = await adminUser
      .from("projects")
      .select("id")
      .eq("id", fx.projectId)
      .maybeSingle();
    expect(error).toBeNull();
    expect(data?.id).toBe(fx.projectId);
  });

  it("knowing project UUID does not bypass access for unassigned engineer", async () => {
    if (!phase2Ready) return;
    const admin = adminClient();
    await admin
      .from("project_members")
      .update({ is_active: false })
      .eq("project_id", fx.projectId)
      .eq("profile_id", fx.users.engineer.id);

    const eng = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    const { data } = await eng.from("projects").select("id").eq("id", fx.projectId).maybeSingle();
    expect(data).toBeNull();
  });

  it("engineer without membership cannot read Phase 2 rows on inaccessible project", async () => {
    if (!phase2Ready) return;
    const admin = adminClient();
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);

    await admin
      .from("project_members")
      .update({ is_active: false })
      .eq("project_id", fx.projectId)
      .eq("profile_id", fx.users.engineer.id);

    const { data: rfiDoc, error: rfiDocErr } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "RFI",
      p_discipline_code: "GENERAL",
      p_title: "Scoped RFI deny",
      p_confidentiality: "internal",
    });
    expect(rfiDocErr).toBeNull();

    await admin.from("rfis").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      document_id: rfiDoc.id,
      rfi_number: rfiDoc.document_number,
      subject: "Scoped deny",
      question: "Must not be visible to unassigned engineer",
      raised_by: fx.users.pm.id,
      responsible_engineer_id: fx.users.pm.id,
      status: "submitted",
      created_by: fx.users.pm.id,
    });

    const { data: matDoc } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "MAT",
      p_discipline_code: "GENERAL",
      p_title: "Scoped MAT",
      p_confidentiality: "internal",
    });
    await admin.from("material_submittals").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      document_id: matDoc.id,
      mat_number: matDoc.document_number,
      material_category: "Cable",
      status: "draft",
      created_by: fx.users.pm.id,
    });

    const { data: shdDoc } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "SHD",
      p_discipline_code: "GENERAL",
      p_title: "Scoped SHD",
      p_confidentiality: "internal",
    });
    await admin.from("shop_drawings").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      document_id: shdDoc.id,
      shd_number: shdDoc.document_number,
      drawing_title: "Scoped drawing",
      status: "draft",
      created_by: fx.users.pm.id,
    });

    const { data: msDoc } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "MS",
      p_discipline_code: "GENERAL",
      p_title: "Scoped MS",
      p_confidentiality: "internal",
    });
    await admin.from("method_statements").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      document_id: msDoc.id,
      ms_number: msDoc.document_number,
      activity: "Scoped activity",
      status: "draft",
      created_by: fx.users.pm.id,
    });

    const { data: irDoc } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "IR",
      p_discipline_code: "GENERAL",
      p_title: "Scoped IR",
      p_confidentiality: "internal",
    });
    await admin.from("inspection_requests").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      document_id: irDoc.id,
      ir_number: irDoc.document_number,
      related_activity: "Scoped IR",
      status: "draft",
      created_by: fx.users.pm.id,
    });

    const { data: ncrDoc } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "NCR",
      p_discipline_code: "GENERAL",
      p_title: "Scoped NCR",
      p_confidentiality: "internal",
    });
    await admin.from("ncrs").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      document_id: ncrDoc.id,
      ncr_number: ncrDoc.document_number,
      description: "Scoped NCR must stay hidden",
      severity: "medium",
      status: "open",
      reported_by: fx.users.pm.id,
      created_by: fx.users.pm.id,
    });

    const { data: trn } = await admin
      .from("transmittals")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        transmittal_number: `TRN-DENY-${Date.now()}`,
        direction: "outgoing",
        recipient: "Consultant",
        subject: "Scoped deny",
        status: "draft",
        created_by: fx.users.pm.id,
      })
      .select("id")
      .single();

    const eng = await signInAs(fx.users.engineer.email, fx.users.engineer.password);

    const checks = await Promise.all([
      eng.from("rfis").select("id").eq("project_id", fx.projectId),
      eng.from("material_submittals").select("id").eq("project_id", fx.projectId),
      eng.from("shop_drawings").select("id").eq("project_id", fx.projectId),
      eng.from("method_statements").select("id").eq("project_id", fx.projectId),
      eng.from("inspection_requests").select("id").eq("project_id", fx.projectId),
      eng.from("ncrs").select("id").eq("project_id", fx.projectId),
      eng.from("transmittals").select("id").eq("project_id", fx.projectId),
    ]);

    for (const result of checks) {
      expect(result.data ?? []).toEqual([]);
    }

    // Cleanup
    await admin.from("transmittals").delete().eq("id", trn!.id);
    for (const docId of [rfiDoc.id, matDoc.id, shdDoc.id, msDoc.id, irDoc.id, ncrDoc.id]) {
      await admin.from("rfis").delete().eq("document_id", docId);
      await admin.from("material_submittals").delete().eq("document_id", docId);
      await admin.from("shop_drawings").delete().eq("document_id", docId);
      await admin.from("method_statements").delete().eq("document_id", docId);
      await admin.from("inspection_requests").delete().eq("document_id", docId);
      await admin.from("ncrs").delete().eq("document_id", docId);
      await admin.from("document_versions").delete().eq("document_id", docId);
      await admin.from("documents").delete().eq("id", docId);
    }
  });

  it("engineer with membership can read RFI on assigned project", async () => {
    if (!phase2Ready) return;
    const admin = adminClient();
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);

    await admin.from("project_members").upsert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      profile_id: fx.users.engineer.id,
      role_label: "engineer",
      is_active: true,
    });

    const { data: doc } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "RFI",
      p_discipline_code: "GENERAL",
      p_title: "Member RFI",
      p_confidentiality: "internal",
    });

    await admin.from("rfis").insert({
      organization_id: fx.orgAId,
      project_id: fx.projectId,
      document_id: doc.id,
      rfi_number: doc.document_number,
      subject: "Visible to member",
      question: "Should be visible",
      raised_by: fx.users.pm.id,
      responsible_engineer_id: fx.users.pm.id,
      status: "submitted",
      created_by: fx.users.pm.id,
    });

    const eng = await signInAs(fx.users.engineer.email, fx.users.engineer.password);
    const { data, error } = await eng.from("rfis").select("id").eq("document_id", doc.id);
    expect(error).toBeNull();
    expect((data ?? []).length).toBe(1);

    await admin
      .from("project_members")
      .update({ is_active: false })
      .eq("project_id", fx.projectId)
      .eq("profile_id", fx.users.engineer.id);
    await admin.from("rfis").delete().eq("document_id", doc.id);
    await admin.from("document_versions").delete().eq("document_id", doc.id);
    await admin.from("documents").delete().eq("id", doc.id);
  });

  it("A–E decision D requires comments; C marks resubmit", async () => {
    if (!phase2Ready) return;
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);
    const admin = adminClient();

    const { data: doc, error } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "SHD",
      p_discipline_code: "GENERAL",
      p_title: "Decision test drawing",
      p_confidentiality: "internal",
    });
    expect(error).toBeNull();

    const rejectNoComment = await pm.rpc("apply_document_approval_decision", {
      p_document_id: doc.id,
      p_official_code: "D",
      p_comments: null,
    });
    expect(rejectNoComment.error?.message ?? "").toMatch(/VALIDATION/i);

    const resubmit = await pm.rpc("apply_document_approval_decision", {
      p_document_id: doc.id,
      p_official_code: "C",
      p_comments: "Revise dimensions",
    });
    expect(resubmit.error).toBeNull();
    expect(resubmit.data?.official_decision).toBe("C");

    await admin.from("document_versions").delete().eq("document_id", doc.id);
    await admin.from("documents").delete().eq("id", doc.id);
  });

  it("compute_project_health returns green|amber|red", async () => {
    if (!phase2Ready) return;
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);
    const { data, error } = await pm.rpc("compute_project_health", {
      p_project_id: fx.projectId,
    });
    expect(error).toBeNull();
    expect(["green", "amber", "red"]).toContain(data);
  });

  it("issued transmittal items are immutable and keep revision snapshot", async () => {
    if (!phase2Ready) return;
    const pm = await signInAs(fx.users.pm.email, fx.users.pm.password);
    const admin = adminClient();

    const { data: doc } = await pm.rpc("register_controlled_document", {
      p_organization_id: fx.orgAId,
      p_project_id: fx.projectId,
      p_type_code: "MAT",
      p_discipline_code: "GENERAL",
      p_title: "Transmittal item",
      p_confidentiality: "internal",
    });
    expect(doc?.id).toBeTruthy();

    const { data: versionR00 } = await admin
      .from("document_versions")
      .select("id, revision")
      .eq("document_id", doc.id)
      .eq("is_current", true)
      .single();
    expect(versionR00?.revision).toBe("R00");

    const { data: trn, error: trnErr } = await pm
      .from("transmittals")
      .insert({
        organization_id: fx.orgAId,
        project_id: fx.projectId,
        transmittal_number: `TRN-LIVE-${Date.now()}`,
        direction: "outgoing",
        recipient: "Consultant",
        subject: "Live immutability",
        status: "draft",
        created_by: fx.users.pm.id,
      })
      .select("id")
      .single();
    expect(trnErr).toBeNull();

    const { data: item, error: itemErr } = await pm
      .from("transmittal_items")
      .insert({
        organization_id: fx.orgAId,
        transmittal_id: trn!.id,
        document_id: doc.id,
        document_version_id: versionR00!.id,
        purpose: "for_approval",
      })
      .select("id, document_version_id")
      .single();
    expect(itemErr).toBeNull();

    const { error: issueErr } = await pm.rpc("issue_transmittal", {
      p_transmittal_id: trn!.id,
    });
    expect(issueErr).toBeNull();

    // Create a newer revision AFTER issue — historical item must keep R00 version id
    const { data: revised } = await pm.rpc("create_document_revision", {
      p_document_id: doc.id,
      p_change_description: "Later revision must not rewrite issued snapshot",
    });
    expect(revised?.current_revision).toBe("R01");

    const { data: snapshot } = await pm
      .from("transmittal_items")
      .select("document_version_id")
      .eq("id", item!.id)
      .single();
    expect(snapshot?.document_version_id).toBe(versionR00!.id);

    const { error: mutateErr } = await pm
      .from("transmittal_items")
      .update({ notes: "should fail" })
      .eq("id", item!.id);
    expect(mutateErr, "UPDATE after issue must error").toBeTruthy();
    expect(mutateErr?.message ?? "").toMatch(/immutable/i);

    const { error: insertErr } = await pm.from("transmittal_items").insert({
      organization_id: fx.orgAId,
      transmittal_id: trn!.id,
      document_id: doc.id,
      document_version_id: versionR00!.id,
      purpose: "for_record",
    });
    expect(insertErr, "INSERT after issue must error").toBeTruthy();

    const { error: deleteErr } = await pm.from("transmittal_items").delete().eq("id", item!.id);
    expect(deleteErr, "DELETE after issue must error").toBeTruthy();
    expect(deleteErr?.message ?? "").toMatch(/immutable/i);

    // Service-role cleanup (ops bypass)
    await admin.from("transmittal_items").delete().eq("transmittal_id", trn!.id);
    await admin.from("transmittals").delete().eq("id", trn!.id);
    await admin.from("document_versions").delete().eq("document_id", doc.id);
    await admin.from("documents").delete().eq("id", doc.id);
  });
});
