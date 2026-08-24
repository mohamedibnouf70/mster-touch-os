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
} from "lucide-react";
import { cn } from "@/lib/utils";

const primary = [
  { href: "/", label: "الرئيسية", icon: LayoutDashboard },
  { href: "/projects", label: "المشاريع", icon: FolderKanban },
  { href: "/engineering", label: "الهندسة", icon: Wrench },
  { href: "/document-control", label: "مراقبة الوثائق", icon: ClipboardList },
  { href: "/search", label: "بحث الوثائق", icon: Search },
  { href: "/approvals", label: "الموافقات", icon: Stamp },
  { href: "/documents", label: "المستندات", icon: FileText },
  { href: "/employees", label: "الموظفون", icon: Users },
  { href: "/departments", label: "الإدارات", icon: Building2 },
  { href: "/notifications", label: "التنبيهات", icon: Bell },
  { href: "/settings", label: "الإعدادات", icon: Settings },
];

const later = [
  { label: "المالية" },
  { label: "المشتريات" },
  { label: "الموارد البشرية" },
  { label: "الجودة والسلامة" },
  { label: "التقارير" },
  { label: "الذكاء الاصطناعي" },
];

export function Sidebar() {
  const pathname = usePathname();
  return (
    <aside className="flex h-full w-72 shrink-0 flex-col border-l border-white/10 bg-navy text-white">
      <div className="border-b border-white/10 px-5 py-5">
        <p className="text-[11px] font-semibold tracking-[0.22em] text-bronze">MASTER TOUCH</p>
        <h1 className="mt-1 text-lg font-semibold">نظام التشغيل</h1>
      </div>
      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
        {primary.map((item) => {
          const Icon = item.icon;
          const active = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition",
                active ? "bg-white/12 text-white" : "text-white/75 hover:bg-white/8 hover:text-white",
              )}
            >
              <Icon className="h-4 w-4" />
              {item.label}
            </Link>
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
