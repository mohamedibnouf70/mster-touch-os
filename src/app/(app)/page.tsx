import Link from "next/link";
import { redirect } from "next/navigation";
import { Card, PageHeader } from "@/components/ui/primitives";
import { getAuthContext } from "@/server/context";
import { CoreRepository } from "@/server/repositories/core.repository";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { hasPermission } from "@/server/policies/authorize";
import { commercialEntityHref } from "@/lib/commercial/entity-routes";

export default async function DashboardPage() {
  const ctx = await getAuthContext();
  if (!ctx) redirect("/login");

  const supabase = await createServerSupabaseClient();
  const repo = new CoreRepository(supabase);
  const dashboard = await repo.dashboard(ctx.organization.id, ctx.userId);
  const canReadAudit = hasPermission(ctx, "audit.read");

  // Procurement My Actions — pulled live
  type ProcAction = { id: string; label: string; href: string; status: string; overdue: boolean };
  const procActions: ProcAction[] = [];
  const today = new Date().toISOString().slice(0, 10);

  if (hasPermission(ctx, "purchase_request.approve")) {
    const { data: prSteps } = await supabase
      .from("approval_steps")
      .select("id, due_at, approval_requests(entity_type, entity_id, title)")
      .eq("organization_id", ctx.organization.id)
      .eq("user_id", ctx.userId)
      .eq("status", "pending")
      .limit(20);
    for (const s of prSteps ?? []) {
      const req = Array.isArray(s.approval_requests) ? s.approval_requests[0] : s.approval_requests;
      if (!req) continue;
      const href = commercialEntityHref(req.entity_type, req.entity_id);
      if (href) {
        procActions.push({
          id: s.id,
          label: req.title ?? req.entity_type,
          href,
          status: "بانتظار قراري",
          overdue: Boolean(s.due_at && s.due_at < new Date().toISOString()),
        });
      }
    }
  }

  if (hasPermission(ctx, "rfq.issue")) {
    const { data: rfqsReady } = await supabase
      .from("rfqs")
      .select("id, rfq_number, title, response_due_date")
      .eq("organization_id", ctx.organization.id)
      .in("status", ["draft", "ready_to_issue"])
      .limit(5);
    for (const r of rfqsReady ?? []) {
      procActions.push({
        id: r.id,
        label: `RFQ ${r.rfq_number} — ${r.title}`,
        href: `/procurement/rfqs/${r.id}`,
        status: "يحتاج إصدار",
        overdue: Boolean(r.response_due_date && r.response_due_date < today),
      });
    }
  }

  if (hasPermission(ctx, "quotation.compare")) {
    const { data: rfqsResp } = await supabase
      .from("rfqs")
      .select("id, rfq_number, title")
      .eq("organization_id", ctx.organization.id)
      .eq("status", "responses_received")
      .limit(5);
    for (const r of rfqsResp ?? []) {
      procActions.push({
        id: `cmp-${r.id}`,
        label: `مقارنة عروض ${r.rfq_number}`,
        href: `/procurement/rfqs/${r.id}/comparison`,
        status: "يحتاج مقارنة",
        overdue: false,
      });
    }
  }

  if (hasPermission(ctx, "purchase_order.issue")) {
    const { data: posApproved } = await supabase
      .from("purchase_orders")
      .select("id, po_number")
      .eq("organization_id", ctx.organization.id)
      .eq("status", "approved")
      .limit(5);
    for (const p of posApproved ?? []) {
      procActions.push({
        id: p.id,
        label: `أمر شراء ${p.po_number}`,
        href: `/procurement/purchase-orders/${p.id}`,
        status: "جاهز للإصدار",
        overdue: false,
      });
    }
  }

  if (hasPermission(ctx, "supplier_invoice.review")) {
    const { data: invReview } = await supabase
      .from("supplier_invoices")
      .select("id, invoice_number, due_date, status")
      .eq("organization_id", ctx.organization.id)
      .in("status", ["received", "under_review", "discrepancy"])
      .order("due_date", { ascending: true, nullsFirst: false })
      .limit(5);
    for (const i of invReview ?? []) {
      procActions.push({
        id: i.id,
        label: `فاتورة ${i.invoice_number}`,
        href: `/finance/supplier-invoices/${i.id}`,
        status: i.status === "discrepancy" ? "اختلاف" : "يحتاج مراجعة",
        overdue: Boolean(i.due_date && i.due_date < today),
      });
    }
  }

  if (hasPermission(ctx, "supplier_payment.record")) {
    const { data: invPay } = await supabase
      .from("supplier_invoices")
      .select("id, invoice_number, due_date")
      .eq("organization_id", ctx.organization.id)
      .in("status", ["approved_for_payment", "partially_paid"])
      .order("due_date", { ascending: true, nullsFirst: false })
      .limit(5);
    for (const i of invPay ?? []) {
      procActions.push({
        id: `pay-${i.id}`,
        label: `دفع فاتورة ${i.invoice_number}`,
        href: `/finance/supplier-invoices/${i.id}`,
        status: "بانتظار الصرف",
        overdue: Boolean(i.due_date && i.due_date < today),
      });
    }
  }

  if (hasPermission(ctx, "client_valuation.approve")) {
    const { data: valReview } = await supabase
      .from("client_valuations")
      .select("id, valuation_number, due_date, status")
      .eq("organization_id", ctx.organization.id)
      .in("status", ["internal_review"])
      .limit(5);
    for (const v of valReview ?? []) {
      procActions.push({
        id: v.id,
        label: `مراجعة مستخلص ${v.valuation_number}`,
        href: `/finance/client-valuations/${v.id}`,
        status: "مراجعة داخلية",
        overdue: Boolean(v.due_date && v.due_date < today),
      });
    }
  }

  if (hasPermission(ctx, "client_valuation.submit")) {
    const { data: valSubmit } = await supabase
      .from("client_valuations")
      .select("id, valuation_number, status")
      .eq("organization_id", ctx.organization.id)
      .eq("status", "submitted")
      .limit(5);
    for (const v of valSubmit ?? []) {
      procActions.push({
        id: `vsub-${v.id}`,
        label: `إرسال مستخلص ${v.valuation_number} للعميل`,
        href: `/finance/client-valuations/${v.id}`,
        status: "بانتظار إرسال للعميل",
        overdue: false,
      });
    }
  }

  if (hasPermission(ctx, "client_invoice.issue")) {
    const { data: invDraft } = await supabase
      .from("client_invoices")
      .select("id, invoice_number, due_date")
      .eq("organization_id", ctx.organization.id)
      .eq("status", "draft")
      .limit(5);
    for (const i of invDraft ?? []) {
      procActions.push({
        id: `cinv-${i.id}`,
        label: `إصدار فاتورة ${i.invoice_number}`,
        href: `/finance/client-invoices/${i.id}`,
        status: "مسودة — جاهزة للإصدار",
        overdue: false,
      });
    }
  }

  if (hasPermission(ctx, "client_payment.record")) {
    const { data: arCollect } = await supabase
      .from("client_invoices")
      .select("id, invoice_number, due_date, status")
      .eq("organization_id", ctx.organization.id)
      .in("status", ["issued", "partially_paid", "overdue"])
      .order("due_date", { ascending: true })
      .limit(5);
    for (const i of arCollect ?? []) {
      procActions.push({
        id: `ar-${i.id}`,
        label: `تحصيل ${i.invoice_number}`,
        href: `/finance/client-invoices/${i.id}`,
        status: i.status === "overdue" ? "متأخر" : "بانتظار التحصيل",
        overdue: Boolean(i.due_date && i.due_date < today),
      });
    }
  }

  if (hasPermission(ctx, "variation.approve")) {
    const { data: voPending } = await supabase
      .from("variations")
      .select("id, vo_number, status")
      .eq("organization_id", ctx.organization.id)
      .in("status", ["under_review", "submitted", "negotiation"])
      .limit(5);
    for (const v of voPending ?? []) {
      procActions.push({
        id: v.id,
        label: `اعتماد أمر تغيير ${v.vo_number}`,
        href: `/finance/variations/${v.id}`,
        status: "بانتظار الاعتماد",
        overdue: false,
      });
    }
  }

  procActions.sort((a, b) => (a.overdue === b.overdue ? 0 : a.overdue ? -1 : 1));

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
          {dashboard.pendingActions.length === 0 && procActions.length === 0 ? (
            <p className="text-sm text-muted">لا توجد إجراءات معلقة حالياً.</p>
          ) : (
            <ul className="space-y-3">
              {procActions.slice(0, 15).map((action) => (
                <li key={action.id} className="flex items-center justify-between border-b border-line pb-3 last:border-0">
                  <div>
                    <Link href={action.href} className="text-sm font-medium text-navy underline">
                      {action.label}
                    </Link>
                    <p className="text-xs text-muted">{action.status}</p>
                  </div>
                  <span className={action.overdue ? "text-xs text-danger font-medium" : "text-xs text-muted"}>
                    {action.overdue ? "⚠️ متأخر" : ""}
                  </span>
                </li>
              ))}
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
