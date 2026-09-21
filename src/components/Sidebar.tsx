"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cx, initials } from "@/lib/utils";
import { logoutAction } from "@/actions/auth";
import { Icon, type IconName } from "./icons";

export const NAV_ITEMS: { href: string; label: string; icon: IconName; staffOnly?: boolean }[] = [
  { href: "/dashboard", label: "Dashboard", icon: "dashboard" },
  { href: "/employees", label: "Employees", icon: "users", staffOnly: true },
  { href: "/departments", label: "Departments", icon: "building", staffOnly: true },
  { href: "/attendance", label: "Attendance", icon: "clock" },
  { href: "/leaves", label: "Leaves", icon: "leaf" },
  { href: "/holidays", label: "Holidays", icon: "calendar" },
  { href: "/reports", label: "Reports", icon: "chart", staffOnly: true },
];

export function navFor(role: string) {
  return NAV_ITEMS.filter((n) => !n.staffOnly || role !== "EMPLOYEE");
}

export function Sidebar({ userName, role, companyName }: { userName: string; role: string; companyName: string }) {
  const pathname = usePathname();
  const items = navFor(role);

  return (
    <aside className="flex h-full w-64 flex-col bg-slate-950 text-slate-300">
      {/* Brand */}
      <div className="flex items-center gap-3 px-5 pb-6 pt-6">
        <div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-gradient-to-br from-amber-400 to-amber-600 text-sm font-black text-slate-950 shadow-[0_4px_16px_-2px_rgb(245_158_11_/_50%)]">
          FF
        </div>
        <div className="min-w-0">
          <div className="truncate text-sm font-bold leading-tight text-white">{companyName}</div>
          <div className="text-[11px] font-medium uppercase tracking-widest text-slate-500">HRMS</div>
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 space-y-1 px-3">
        {items.map((item) => {
          const active = pathname === item.href || pathname.startsWith(item.href + "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cx(
                "group relative flex items-center gap-3 rounded-xl px-3.5 py-2.5 text-sm font-medium transition-all",
                active
                  ? "bg-gradient-to-r from-amber-500/15 to-transparent text-amber-400"
                  : "text-slate-400 hover:bg-white/5 hover:text-white"
              )}
            >
              <span
                className={cx(
                  "absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-amber-500 transition-all",
                  active ? "opacity-100" : "opacity-0 group-hover:opacity-40"
                )}
              />
              <Icon name={item.icon} className={cx("h-[18px] w-[18px]", active && "drop-shadow-[0_0_6px_rgb(245_158_11_/_60%)]")} />
              {item.label}
            </Link>
          );
        })}
      </nav>

      {/* User */}
      <div className="border-t border-white/[0.06] p-4">
        <div className="flex items-center gap-3 rounded-xl bg-white/[0.04] p-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-slate-700 to-slate-800 text-xs font-bold text-amber-400 ring-1 ring-white/10">
            {initials(userName)}
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold text-white">{userName}</div>
            <div className="text-[11px] font-medium text-slate-500">{role}</div>
          </div>
          <form action={logoutAction}>
            <button
              title="Sign out"
              className="rounded-lg p-2 text-slate-500 transition hover:bg-red-500/10 hover:text-red-400"
            >
              <Icon name="logout" className="h-4 w-4" />
            </button>
          </form>
        </div>
      </div>
    </aside>
  );
}
