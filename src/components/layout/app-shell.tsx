import { signOutAction } from "@/modules/auth/actions";
import type { AuthContext } from "@/types/models";
import { Button } from "@/components/ui/primitives";
import { Sidebar } from "./sidebar";

export async function AppShell({
  ctx,
  children,
}: {
  ctx: AuthContext;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-line bg-white px-6 py-3">
          <div>
            <p className="text-sm font-medium text-navy">{ctx.organization.name_ar}</p>
            <p className="text-xs text-muted">{ctx.organization.name_en}</p>
          </div>
          <div className="flex items-center gap-3">
            <div className="text-left text-sm">
              <p className="font-medium">{ctx.profile.full_name_ar || ctx.profile.full_name_en || "مستخدم"}</p>
              <p className="text-xs text-muted">{ctx.employee?.job_title_ar ?? "حساب تشغيلي"}</p>
            </div>
            <form action={signOutAction}>
              <Button type="submit" variant="secondary">
                خروج
              </Button>
            </form>
          </div>
        </header>
        <main className="flex-1 px-6 py-6">{children}</main>
      </div>
    </div>
  );
}
