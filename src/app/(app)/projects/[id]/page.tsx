import { notFound, redirect } from "next/navigation";
import { Badge, Button, Card, EmptyState, Field, Input, PageHeader, Select } from "@/components/ui/primitives";
import { getAuthContext } from "@/server/context";
import { hasPermission } from "@/server/policies/authorize";
import { CoreRepository } from "@/server/repositories/core.repository";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import {
  assignProjectMemberAction,
  createApprovalAction,
  startWorkflowAction,
  updateProjectStageAction,
  uploadDocumentAction,
} from "@/server/use-cases/platform";

const laterTabs = ["المالية", "المشتريات", "الهندسة", "السلامة", "الجودة", "الاتصالات", "الذكاء الاصطناعي"];

export default async function ProjectDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const ctx = await getAuthContext();
  if (!ctx || !hasPermission(ctx, "project.read")) redirect("/login");

  const { id } = await params;
  const { tab = "overview" } = await searchParams;
  const supabase = await createServerSupabaseClient();
  const repo = new CoreRepository(supabase);
  const project = await repo.getProject(ctx.organization.id, id);
  if (!project) notFound();

  const [stages, members, documents, users, definitions] = await Promise.all([
    repo.listProjectStages(project.id),
    repo.listProjectMembers(project.id),
    repo.listDocuments(ctx.organization.id, project.id),
    repo.listUsers(ctx.organization.id),
    supabase.from("workflow_definitions").select("id, name_ar").eq("status", "published"),
  ]);

  const canSeeFinance = hasPermission(ctx, "finance.read");
  const tabs = [
    { id: "overview", label: "نظرة عامة" },
    { id: "stages", label: "المراحل" },
    { id: "team", label: "الفريق" },
    { id: "documents", label: "المستندات" },
    { id: "approvals", label: "الموافقات" },
    { id: "activity", label: "النشاط" },
  ];

  return (
    <div>
      <PageHeader
        title={project.name_ar}
        description={`${project.project_code} · ${project.name_en}`}
      />
      <div className="mb-4 flex flex-wrap gap-2">
        <Badge tone="navy">{project.status}</Badge>
        <Badge tone={project.risk_level === "high" || project.risk_level === "critical" ? "danger" : "neutral"}>
          المخاطر: {project.risk_level}
        </Badge>
        <Badge>{project.progress_percentage}%</Badge>
      </div>

      <div className="mb-6 flex flex-wrap gap-2 border-b border-line pb-2">
        {tabs.map((item) => (
          <a
            key={item.id}
            href={`/projects/${project.id}?tab=${item.id}`}
            className={`rounded-md px-3 py-1.5 text-sm ${tab === item.id ? "bg-navy text-white" : "text-muted hover:bg-white"}`}
          >
            {item.label}
          </a>
        ))}
        {laterTabs.map((item) => (
          <span key={item} className="rounded-md px-3 py-1.5 text-sm text-muted/50">
            {item} · لاحقاً
          </span>
        ))}
      </div>

      {tab === "overview" ? (
        <div className="grid gap-4 md:grid-cols-2">
          <Card>
            <h2 className="mb-3 font-semibold text-navy">البيانات الأساسية</h2>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-muted">الموقع</dt>
                <dd>{project.location ?? "—"}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-muted">البداية</dt>
                <dd>{project.start_date ?? "—"}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-muted">الانتهاء المخطط</dt>
                <dd>{project.planned_end_date ?? "—"}</dd>
              </div>
              {canSeeFinance ? (
                <>
                  <div className="flex justify-between gap-4">
                    <dt className="text-muted">قيمة العقد</dt>
                    <dd>{project.contract_value ?? "—"}</dd>
                  </div>
                  <div className="flex justify-between gap-4">
                    <dt className="text-muted">الميزانية</dt>
                    <dd>{project.budget ?? "—"}</dd>
                  </div>
                </>
              ) : null}
            </dl>
          </Card>
          <Card>
            <h2 className="mb-3 font-semibold text-navy">الوصف</h2>
            <p className="text-sm leading-7 text-muted">{project.description ?? "لا يوجد وصف."}</p>
          </Card>
        </div>
      ) : null}

      {tab === "stages" ? (
        <Card className="p-0">
          {stages.length === 0 ? (
            <EmptyState title="لم تُنشأ مراحل لهذا المشروع." />
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-paper text-muted">
                <tr>
                  <th className="px-4 py-3 text-right">#</th>
                  <th className="px-4 py-3 text-right">المرحلة</th>
                  <th className="px-4 py-3 text-right">الحالة</th>
                  <th className="px-4 py-3 text-right">تحديث</th>
                </tr>
              </thead>
              <tbody>
                {stages.map((stage) => (
                  <tr key={stage.id} className="border-t border-line">
                    <td className="px-4 py-3">{stage.sequence}</td>
                    <td className="px-4 py-3">
                      {stage.name_ar}
                      <p className="text-xs text-muted">{stage.name_en}</p>
                    </td>
                    <td className="px-4 py-3">
                      <Badge>{stage.status}</Badge>
                    </td>
                    <td className="px-4 py-3">
                      {hasPermission(ctx, "project.update") ? (
                        <form action={updateProjectStageAction} className="flex gap-2">
                          <input type="hidden" name="stageId" value={stage.id} />
                          <Select name="status" defaultValue={stage.status}>
                            <option value="not_started">لم تبدأ</option>
                            <option value="in_progress">جارية</option>
                            <option value="blocked">معلقة</option>
                            <option value="completed">مكتملة</option>
                            <option value="skipped">متجاوزة</option>
                          </Select>
                          <Button type="submit" variant="secondary">
                            حفظ
                          </Button>
                        </form>
                      ) : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      ) : null}

      {tab === "team" ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <h2 className="mb-3 font-semibold text-navy">أعضاء الفريق</h2>
            {members.length === 0 ? (
              <p className="text-sm text-muted">لا يوجد أعضاء بعد.</p>
            ) : (
              <ul className="space-y-2 text-sm">
                {members.map((member) => {
                  const profile = Array.isArray(member.profiles) ? member.profiles[0] : member.profiles;
                  return (
                    <li key={member.id} className="flex justify-between border-b border-line pb-2">
                      <span>{profile?.full_name_ar || profile?.full_name_en}</span>
                      <span className="text-muted">{member.role_label}</span>
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>
          {hasPermission(ctx, "project.manage_team") ? (
            <Card>
              <h2 className="mb-3 font-semibold text-navy">تعيين عضو</h2>
              <form action={assignProjectMemberAction} className="space-y-3">
                <input type="hidden" name="projectId" value={project.id} />
                <Field label="المستخدم">
                  <Select name="profileId" required>
                    {users.map((row) => {
                      const profile = Array.isArray(row.profiles) ? row.profiles[0] : row.profiles;
                      return (
                        <option key={row.profile_id} value={row.profile_id}>
                          {profile?.full_name_ar || row.profile_id}
                        </option>
                      );
                    })}
                  </Select>
                </Field>
                <Field label="الدور في المشروع">
                  <Input name="roleLabel" defaultValue="member" />
                </Field>
                <Button type="submit">تعيين</Button>
              </form>
            </Card>
          ) : null}
        </div>
      ) : null}

      {tab === "documents" ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <h2 className="mb-3 font-semibold text-navy">مستندات المشروع</h2>
            {documents.length === 0 ? (
              <p className="text-sm text-muted">لا توجد مستندات.</p>
            ) : (
              <ul className="space-y-2 text-sm">
                {documents.map((doc) => (
                  <li key={doc.id} className="flex justify-between border-b border-line pb-2">
                    <span>{doc.title}</span>
                    <span className="text-muted">
                      {doc.category} · {doc.current_revision}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
          {hasPermission(ctx, "document.upload") ? (
            <Card>
              <h2 className="mb-3 font-semibold text-navy">رفع مستند</h2>
              <form action={uploadDocumentAction} className="space-y-3">
                <input type="hidden" name="projectId" value={project.id} />
                <Field label="العنوان">
                  <Input name="title" required />
                </Field>
                <Field label="التصنيف">
                  <Select name="category" defaultValue="business_case">
                    <option value="business_case">دراسة الجدوى</option>
                    <option value="contract">عقد</option>
                    <option value="drawing">مخطط</option>
                    <option value="other">أخرى</option>
                  </Select>
                </Field>
                <Field label="الملف">
                  <Input name="file" type="file" required />
                </Field>
                <Button type="submit">رفع</Button>
              </form>
            </Card>
          ) : null}
        </div>
      ) : null}

      {tab === "approvals" ? (
        <div className="grid gap-4 lg:grid-cols-2">
          {hasPermission(ctx, "approval.create") ? (
            <Card>
              <h2 className="mb-3 font-semibold text-navy">طلب موافقة</h2>
              <form action={createApprovalAction} className="space-y-3">
                <input type="hidden" name="entityType" value="project" />
                <input type="hidden" name="entityId" value={project.id} />
                <Field label="العنوان">
                  <Input name="title" defaultValue={`موافقة مشروع ${project.project_code}`} required />
                </Field>
                <Field label="المعتمد">
                  <Select name="approverProfileId" required>
                    {users.map((row) => {
                      const profile = Array.isArray(row.profiles) ? row.profiles[0] : row.profiles;
                      return (
                        <option key={row.profile_id} value={row.profile_id}>
                          {profile?.full_name_ar || row.profile_id}
                        </option>
                      );
                    })}
                  </Select>
                </Field>
                <Button type="submit">إنشاء طلب</Button>
              </form>
            </Card>
          ) : null}
          {hasPermission(ctx, "workflow.start") ? (
            <Card>
              <h2 className="mb-3 font-semibold text-navy">بدء مسار عمل</h2>
              <form action={startWorkflowAction} className="space-y-3">
                <input type="hidden" name="entityType" value="project" />
                <input type="hidden" name="entityId" value={project.id} />
                <Field label="القالب">
                  <Select name="definitionId" required>
                    {(definitions.data ?? []).map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.name_ar}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Button type="submit">بدء</Button>
              </form>
            </Card>
          ) : null}
        </div>
      ) : null}

      {tab === "activity" ? (
        <Card>
          <p className="text-sm text-muted">
            النشاط التفصيلي يظهر في السجل العام عند توفر صلاحية التدقيق، مع الحفاظ على الطوابع الزمنية التاريخية.
          </p>
        </Card>
      ) : null}
    </div>
  );
}
