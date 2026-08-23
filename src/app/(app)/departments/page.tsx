import { redirect } from "next/navigation";
import { Badge, Card, EmptyState, PageHeader } from "@/components/ui/primitives";
import { getAuthContext } from "@/server/context";
import { hasPermission } from "@/server/policies/authorize";
import { CoreRepository } from "@/server/repositories/core.repository";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export default async function DepartmentsPage() {
  const ctx = await getAuthContext();
  if (!ctx || !hasPermission(ctx, "department.read")) redirect("/login");

  const supabase = await createServerSupabaseClient();
  const repo = new CoreRepository(supabase);
  const departments = await repo.listDepartments(ctx.organization.id);

  return (
    <div>
      <PageHeader
        title="الإدارات"
        description="هيكل إدارات قابل للتهيئة من قاعدة البيانات وليس تعداداً ثابتاً في الواجهة"
      />

      {departments.length === 0 ? (
        <EmptyState title="لا توجد إدارات." />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {departments.map((department) => (
            <Card key={department.id}>
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="text-xs font-semibold tracking-wide text-bronze">{department.code}</p>
                  <h2 className="mt-1 text-base font-semibold text-navy">{department.name_ar}</h2>
                  <p className="text-sm text-muted">{department.name_en}</p>
                </div>
                <Badge tone={department.is_active ? "success" : "neutral"}>
                  {department.is_active ? "نشطة" : "موقوفة"}
                </Badge>
              </div>
              {department.description ? (
                <p className="mt-3 text-sm text-muted">{department.description}</p>
              ) : null}
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
