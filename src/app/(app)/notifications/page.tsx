import { redirect } from "next/navigation";
import { Badge, Button, Card, EmptyState, PageHeader } from "@/components/ui/primitives";
import { getAuthContext } from "@/server/context";
import { hasPermission } from "@/server/policies/authorize";
import { CoreRepository } from "@/server/repositories/core.repository";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { markNotificationReadAction } from "@/server/use-cases/platform";

export default async function NotificationsPage() {
  const ctx = await getAuthContext();
  if (!ctx || !hasPermission(ctx, "notification.read")) redirect("/login");

  const supabase = await createServerSupabaseClient();
  const repo = new CoreRepository(supabase);
  const notifications = await repo.listNotifications(ctx.userId);

  return (
    <div>
      <PageHeader title="التنبيهات" description="قناة داخلية للتطبيق — البريد وواتساب لاحقاً عبر نفس الخدمة" />

      {notifications.length === 0 ? (
        <EmptyState title="لا توجد تنبيهات." />
      ) : (
        <div className="space-y-3">
          {notifications.map((item) => (
            <Card key={item.id} className={item.read_at ? "opacity-70" : undefined}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div className="mb-1 flex items-center gap-2">
                    <h2 className="text-sm font-semibold text-navy">{item.title}</h2>
                    <Badge
                      tone={
                        item.priority === "urgent" || item.priority === "high" ? "danger" : "neutral"
                      }
                    >
                      {item.priority}
                    </Badge>
                    {!item.read_at ? <Badge tone="navy">جديد</Badge> : null}
                  </div>
                  <p className="text-sm text-muted">{item.message}</p>
                  <p className="mt-2 text-xs text-muted">
                    {item.type} ·{" "}
                    {new Date(item.created_at).toLocaleString("ar-SA", { timeZone: "Asia/Riyadh" })}
                  </p>
                </div>
                {!item.read_at ? (
                  <form action={markNotificationReadAction}>
                    <input type="hidden" name="id" value={item.id} />
                    <Button type="submit" variant="secondary">
                      تعليم كمقروء
                    </Button>
                  </form>
                ) : null}
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
