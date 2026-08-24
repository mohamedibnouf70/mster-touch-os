import { redirect } from "next/navigation";
import Link from "next/link";
import { Badge, Card, EmptyState, Field, PageHeader } from "@/components/ui/primitives";
import { getAuthContext } from "@/server/context";
import { hasPermission } from "@/server/policies/authorize";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const ctx = await getAuthContext();
  if (!ctx) redirect("/login");

  const { q = "" } = await searchParams;
  const term = q.trim();
  const supabase = await createServerSupabaseClient();

  type Hit = { kind: string; number: string; title: string; href: string; status?: string };

  const hits: Hit[] = [];

  if (term.length >= 2) {
    const pattern = `%${term}%`;
    const [docs, rfis, mats, shds, irs, ncrs, trns, cors] = await Promise.all([
      supabase
        .from("documents")
        .select("id, document_number, title, type_code, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`document_number.ilike.${pattern},title.ilike.${pattern}`)
        .limit(20),
      supabase
        .from("rfis")
        .select("id, rfi_number, subject, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`rfi_number.ilike.${pattern},subject.ilike.${pattern}`)
        .limit(15),
      supabase
        .from("material_submittals")
        .select("id, mat_number, material_category, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`mat_number.ilike.${pattern},material_category.ilike.${pattern}`)
        .limit(15),
      supabase
        .from("shop_drawings")
        .select("id, shd_number, drawing_title, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`shd_number.ilike.${pattern},drawing_title.ilike.${pattern}`)
        .limit(15),
      supabase
        .from("inspection_requests")
        .select("id, ir_number, related_activity, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`ir_number.ilike.${pattern},related_activity.ilike.${pattern}`)
        .limit(15),
      supabase
        .from("ncrs")
        .select("id, ncr_number, description, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`ncr_number.ilike.${pattern},description.ilike.${pattern}`)
        .limit(15),
      supabase
        .from("transmittals")
        .select("id, transmittal_number, subject, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`transmittal_number.ilike.${pattern},subject.ilike.${pattern}`)
        .limit(15),
      supabase
        .from("correspondence")
        .select("id, reference_number, subject, status, project_id")
        .eq("organization_id", ctx.organization.id)
        .or(`reference_number.ilike.${pattern},subject.ilike.${pattern}`)
        .limit(15),
    ]);

    for (const d of docs.data ?? []) {
      hits.push({
        kind: d.type_code ?? "DOC",
        number: d.document_number ?? d.id,
        title: d.title,
        status: d.status,
        href: `/document-control?q=${encodeURIComponent(d.document_number ?? "")}`,
      });
    }
    for (const r of rfis.data ?? []) {
      hits.push({
        kind: "RFI",
        number: r.rfi_number,
        title: r.subject,
        status: r.status,
        href: `/engineering?module=rfi&project=${r.project_id}`,
      });
    }
    for (const m of mats.data ?? []) {
      hits.push({
        kind: "MAT",
        number: m.mat_number,
        title: m.material_category,
        status: m.status,
        href: `/engineering?module=mat&project=${m.project_id}`,
      });
    }
    for (const s of shds.data ?? []) {
      hits.push({
        kind: "SHD",
        number: s.shd_number,
        title: s.drawing_title,
        status: s.status,
        href: `/engineering?module=shd&project=${s.project_id}`,
      });
    }
    for (const i of irs.data ?? []) {
      hits.push({
        kind: "IR",
        number: i.ir_number,
        title: i.related_activity ?? "",
        status: i.status,
        href: `/engineering?module=ir&project=${i.project_id}`,
      });
    }
    for (const n of ncrs.data ?? []) {
      hits.push({
        kind: "NCR",
        number: n.ncr_number,
        title: n.description,
        status: n.status,
        href: `/engineering?module=ncr&project=${n.project_id}`,
      });
    }
    for (const t of trns.data ?? []) {
      hits.push({
        kind: "TRN",
        number: t.transmittal_number,
        title: t.subject,
        status: t.status,
        href: `/document-control?q=${encodeURIComponent(t.transmittal_number)}`,
      });
    }
    for (const c of cors.data ?? []) {
      hits.push({
        kind: "COR",
        number: c.reference_number,
        title: c.subject,
        status: c.status,
        href: `/projects/${c.project_id}?tab=correspondence`,
      });
    }
  }

  const canSearch =
    hasPermission(ctx, "document.read") ||
    hasPermission(ctx, "document_control.read") ||
    hasPermission(ctx, "engineering.read") ||
    hasPermission(ctx, "rfi.read");

  if (!canSearch) redirect("/");

  return (
    <div>
      <PageHeader title="بحث الوثائق" description="بحث من جانب قاعدة البيانات بالأرقام والعناوين" />
      <Card className="mb-6">
        <form className="flex flex-wrap gap-3">
          <Field label="رقم الوثيقة / العنوان">
            <input
              name="q"
              defaultValue={term}
              className="w-full min-w-[280px] rounded-md border border-line bg-white px-3 py-2 text-sm"
              placeholder="مثال: RFI- أو MAT- أو عنوان..."
            />
          </Field>
          <div className="flex items-end">
            <button type="submit" className="rounded-md bg-navy px-4 py-2 text-sm text-white">
              بحث
            </button>
          </div>
        </form>
      </Card>

      {term.length < 2 ? (
        <EmptyState title="أدخل حرفين على الأقل للبحث." />
      ) : hits.length === 0 ? (
        <EmptyState title="لا توجد نتائج ضمن نطاق صلاحياتك." />
      ) : (
        <Card className="p-0">
          <table className="w-full text-sm">
            <thead className="bg-paper text-muted">
              <tr>
                <th className="px-4 py-3 text-right">النوع</th>
                <th className="px-4 py-3 text-right">الرقم</th>
                <th className="px-4 py-3 text-right">العنوان</th>
                <th className="px-4 py-3 text-right">الحالة</th>
              </tr>
            </thead>
            <tbody>
              {hits.map((hit, idx) => (
                <tr key={`${hit.kind}-${hit.number}-${idx}`} className="border-t border-line">
                  <td className="px-4 py-3">
                    <Badge tone="navy">{hit.kind}</Badge>
                  </td>
                  <td className="px-4 py-3">
                    <Link href={hit.href} className="font-medium text-navy underline">
                      {hit.number}
                    </Link>
                  </td>
                  <td className="px-4 py-3">{hit.title}</td>
                  <td className="px-4 py-3 text-muted">{hit.status ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </div>
  );
}
