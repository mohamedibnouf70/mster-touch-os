import Link from "next/link";
import { redirect } from "next/navigation";
import { Card, PageHeader } from "@/components/ui/primitives";
import { getAuthContext } from "@/server/context";
import { CoreRepository } from "@/server/repositories/core.repository";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { hasPermission } from "@/server/policies/authorize";

export default async function DashboardPage() {
  const ctx = await getAuthContext();
  if (!ctx) redirect("/login");

  const supabase = await createServerSupabaseClient();
  const repo = new CoreRepository(supabase);
  const dashboard = await repo.dashboard(ctx.organization.id, ctx.userId);
  const canReadAudit = hasPermission(ctx, "audit.read");

  const cards = [
    { label: "المشاريع النشطة", value: dashboard.stats.activeProjects, href: "/projects" },
    { label: "مشاريع عالية المخاطر", value: dashboard.stats.projectsAtRisk, href: "/projects?risk=high" },
    { label: "موافقات معلّقة", value: dashboard.stats.pendingApprovals, href: "/approvals" },
    { label: "موافقات متأخرة", value: dashboard.stats.overdueApprovals, href: "/approvals?overdue=1" },
    { label: "موظفون نشطون", value: dashboard.stats.activeEmployees, href: "/employees" },
    { label: "تنبيهات غير مقروءة", value: dashboard.stats.unreadNotifications, href: "/notifications" },
  ];

  return (
    <div>
      <PageHeader title="الرئيسية" description="ملخص تشغيلي من البيانات الفعلية للنظام" />
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {cards.map((card) => (
          <Link key={card.label} href={card.href}>
            <Card className="transition hover:border-navy/30">
              <p className="text-sm text-muted">{card.label}</p>
              <p className="mt-2 text-3xl font-semibold text-navy">{card.value}</p>
            </Card>
          </Link>
        ))}
      </div>

      <div className="mt-8 grid gap-6 xl:grid-cols-2">
        <Card>
          <h2 className="mb-4 text-lg font-semibold text-navy">إجراءاتي المعلقة</h2>
          {dashboard.pendingActions.length === 0 ? (
            <p className="text-sm text-muted">لا توجد إجراءات معلقة حالياً.</p>
          ) : (
            <ul className="space-y-3">
              {dashboard.pendingActions.map((action) => (
                <li key={action.id} className="flex items-center justify-between border-b border-line pb-3 last:border-0">
                  <div>
                    <p className="text-sm font-medium">{action.title}</p>
                    <p className="text-xs text-muted">
                      {action.kind === "approval"
                        ? "موافقة"
                        : action.kind === "workflow"
                          ? "مسار عمل"
                          : action.kind === "rfi"
                            ? "طلب استفسار"
                            : action.kind === "ncr"
                              ? "عدم مطابقة"
                              : action.kind === "document_revision"
                                ? "مراجعة وثيقة"
                                : action.kind === "inspection"
                                  ? "فحص"
                                  : "إجراء"}
                    </p>
                  </div>
                  <span className={action.isOverdue ? "text-xs text-danger" : "text-xs text-muted"}>
                    {action.isOverdue ? "متأخر" : action.dueAt ? "ضمن المهلة" : "بدون مهلة"}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card>
          <h2 className="mb-4 text-lg font-semibold text-navy">آخر النشاطات</h2>
          {!canReadAudit ? (
            <p className="text-sm text-muted">عرض سجل النشاط يتطلب صلاحية التدقيق.</p>
          ) : dashboard.recentActivity.length === 0 ? (
            <p className="text-sm text-muted">لا يوجد نشاط مسجّل بعد.</p>
          ) : (
            <ul className="space-y-3">
              {dashboard.recentActivity.map((item) => (
                <li key={item.id} className="border-b border-line pb-3 last:border-0">
                  <p className="text-sm font-medium">{item.action}</p>
                  <p className="text-xs text-muted">
                    {item.entity_type} · {new Date(item.created_at).toLocaleString("ar-SA", { timeZone: "Asia/Riyadh" })}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
