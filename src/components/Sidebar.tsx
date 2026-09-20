"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cx } from "@/lib/utils";
import { logoutAction } from "@/actions/auth";
import { initials } from "@/lib/utils";

type NavItem = { href: string; label: string; icon: string; staffOnly?: boolean };

const NAV: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", icon: "▦" },
  { href: "/employees", label: "Employees", icon: "👥", staffOnly: true },
  { href: "/departments", label: "Departments", icon: "🏢", staffOnly: true },
  { href: "/attendance", label: "Attendance", icon: "⏰" },
  { href: "/leaves", label: "Leaves", icon: "🌴" },
  { href: "/holidays", label: "Holidays", icon: "📅" },
];

export function Sidebar({
  userName,
  role,
  companyName,
}: {
  userName: string;
  role: string;
  companyName: string;
}) {
  const pathname = usePathname();
  const items = NAV.filter((n) => !n.staffOnly || role !== "EMPLOYEE");

  return (
    <aside className="flex h-full w-64 flex-col bg-slate-950 text-slate-300">
      <div className="flex items-center gap-3 px-5 py-5">
        <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-amber-500 text-sm font-black text-slate-950">
          FF
        </div>
        <div>
          <div className="text-sm font-semibold text-white leading-tight">{companyName}</div>
          <div className="text-xs text-slate-500">HRMS</div>
        </div>
      </div>

      <nav className="mt-2 flex-1 space-y-1 px-3">
        {items.map((item) => {
          const active = pathname === item.href || pathname.startsWith(item.href + "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cx(
                "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                active ? "bg-amber-500/10 text-amber-400" : "text-slate-400 hover:bg-white/5 hover:text-white"
              )}
            >
              <span aria-hidden className="w-5 text-center text-base">{item.icon}</span>
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="border-t border-white/10 p-4">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-slate-800 text-xs font-bold text-amber-400">
            {initials(userName)}
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-medium text-white">{userName}</div>
            <div className="text-xs text-slate-500">{role}</div>
          </div>
          <form action={logoutAction}>
            <button
              title="Sign out"
              className="rounded-lg px-2 py-1.5 text-slate-500 hover:bg-white/10 hover:text-white"
            >
              ⏻
            </button>
          </form>
        </div>
      </div>
    </aside>
  );
}
