"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Bell,
  Building2,
  ClipboardList,
  FileText,
  FolderKanban,
  LayoutDashboard,
  Search,
  Settings,
  Stamp,
  Users,
  Wrench,
  ShoppingCart,
  Wallet,
} from "lucide-react";
import { cn } from "@/lib/utils";

const primary = [
  { href: "/", label: "الرئيسية", icon: LayoutDashboard },
  { href: "/projects", label: "المشاريع", icon: FolderKanban },
  { href: "/engineering", label: "الهندسة", icon: Wrench },
  { href: "/document-control", label: "مراقبة الوثائق", icon: ClipboardList },
  { href: "/procurement", label: "المشتريات", icon: ShoppingCart },
  { href: "/finance", label: "المالية", icon: Wallet },
  { href: "/search", label: "بحث موحّد", icon: Search },
  { href: "/approvals", label: "الموافقات", icon: Stamp },
  { href: "/documents", label: "المستندات", icon: FileText },
  { href: "/employees", label: "الموظفون", icon: Users },
  { href: "/departments", label: "الإدارات", icon: Building2 },
  { href: "/notifications", label: "التنبيهات", icon: Bell },
  { href: "/settings", label: "الإعدادات", icon: Settings },
];

const financeSubLinks = [
  { href: "/finance", label: "لوحة المالية", exact: true },
  { href: "/finance/supplier-invoices", label: "فواتير الموردين" },
  { href: "/finance/client-valuations", label: "مستخلصات العملاء" },
  { href: "/finance/client-invoices", label: "فواتير العملاء" },
  { href: "/finance/variations", label: "أوامر التغيير" },
  { href: "/finance/receivables", label: "ذمم العملاء" },
];

const later = [{ label: "الجودة والسلامة" }, { label: "الذكاء الاصطناعي" }];

export function Sidebar({
  canEmployees = true,
  canDepartments = true,
}: {
  canEmployees?: boolean;
  canDepartments?: boolean;
}) {
  const pathname = usePathname();
  const onFinance = pathname.startsWith("/finance");
  const links = primary.filter((item) => {
    if (item.href === "/employees") return canEmployees;
    if (item.href === "/departments") return canDepartments;
    return true;
  });

  return (
    <aside className="flex h-full w-72 shrink-0 flex-col border-l border-white/10 bg-navy text-white">
      <div className="border-b border-white/10 px-5 py-5">
        <p className="text-[11px] font-semibold tracking-[0.22em] text-bronze">MASTER TOUCH</p>
        <h1 className="mt-1 text-lg font-semibold">نظام التشغيل</h1>
      </div>
      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
        {links.map((item) => {
          const Icon = item.icon;
          const active = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href);
          const isFinance = item.href === "/finance";
          return (
            <div key={item.href}>
              <Link
                href={item.href}
                className={cn(
                  "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition",
                  active ? "bg-white/12 text-white" : "text-white/75 hover:bg-white/8 hover:text-white",
                )}
              >
                <Icon className="h-4 w-4" />
                {item.label}
              </Link>
              {isFinance && onFinance ? (
                <div className="me-2 mt-1 space-y-0.5 border-r border-white/10 pe-2">
                  {financeSubLinks.map((sub) => {
                    const subActive = sub.exact ? pathname === sub.href : pathname.startsWith(sub.href);
                    return (
                      <Link
                        key={sub.href}
                        href={sub.href}
                        data-testid={`sidebar-${sub.href.replaceAll("/", "-").slice(1)}`}
                        className={cn(
                          "block rounded-md py-1.5 pe-3 ps-6 text-xs transition",
                          subActive ? "bg-white/10 text-white" : "text-white/55 hover:text-white/85",
                        )}
                      >
                        {sub.label}
                      </Link>
                    );
                  })}
                </div>
              ) : null}
            </div>
          );
        })}
        <p className="px-3 pt-6 pb-2 text-[11px] font-semibold tracking-wide text-white/40">وحدات لاحقة</p>
        {later.map((item) => (
          <div
            key={item.label}
            className="flex items-center justify-between rounded-md px-3 py-2 text-sm text-white/35"
          >
            <span>{item.label}</span>
            <span className="text-[10px]">لاحقاً</span>
          </div>
        ))}
      </nav>
    </aside>
  );
}
