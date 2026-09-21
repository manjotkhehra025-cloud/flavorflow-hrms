"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon } from "./icons";
import { logoutAction } from "@/actions/auth";
import { cx } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/dashboard", label: "Dashboard", icon: "home" as const },
  { href: "/employees", label: "Team", icon: "users" as const, staffOnly: true },
  { href: "/attendance", label: "Attendance", icon: "clock" as const },
  { href: "/leaves", label: "Leaves", icon: "leaf" as const },
  { href: "/approvals", label: "Approvals", icon: "check" as const, staffOnly: true },
  { href: "/idcard", label: "ID Card & Gate Pass", icon: "badge" as const },
  { href: "/holidays", label: "Holidays", icon: "calendar" as const },
  { href: "/departments", label: "Departments", icon: "building" as const, staffOnly: true },
  { href: "/reports", label: "Reports", icon: "report" as const, staffOnly: true },
  { href: "/tops", label: "TOPS Weekly", icon: "chart" as const, staffOnly: true },
  { href: "/settings", label: "Settings", icon: "sliders" as const, staffOnly: true },
];

export function HLogo({ className = "h-10 w-10" }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={className}>
      <defs>
        <linearGradient id="hlg1" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#34d399" />
          <stop offset="1" stopColor="#059669" />
        </linearGradient>
        <linearGradient id="hlg2" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#6ee7b7" />
          <stop offset="1" stopColor="#10b981" />
        </linearGradient>
      </defs>
      <rect width="64" height="64" rx="14" fill="url(#hlg1)" />
      <rect x="16" y="16" width="30" height="8.5" rx="4.25" fill="white" fillOpacity="0.92" />
      <rect x="16" y="28" width="22" height="8.5" rx="4.25" fill="#0a1628" fillOpacity="0.85" />
      <rect x="16" y="40" width="27" height="8.5" rx="4.25" fill="white" fillOpacity="0.92" />
      <circle cx="49.75" cy="46" r="5" fill="url(#hlg2)" stroke="white" strokeWidth="1.5" />
    </svg>
  );
}

export function Sidebar({ role, name, companyName }: { role: string; name: string; companyName: string }) {
  const pathname = usePathname();
  const items = NAV_ITEMS.filter((i) => !i.staffOnly || role !== "EMPLOYEE");

  return (
    <aside className="sidebar-content hidden w-64 shrink-0 flex-col bg-[#0a1628] lg:fixed lg:inset-y-0 lg:flex">
      <div className="flex items-center gap-3 px-5 pt-6">
        <HLogo className="h-10 w-10 drop-shadow-[0_4px_14px_rgb(16_185_129_/_40%)]" />
        <div>
          <span className="block text-lg font-extrabold tracking-tight text-white">
            HRMate
          </span>
          <span className="block text-[10px] font-semibold uppercase tracking-wider text-emerald-400/80">
            Workforce Portal
          </span>
        </div>
      </div>

      <nav className="mt-7 flex-1 space-y-0.5 overflow-y-auto px-3">
        {items.map((item) => {
          const active = pathname === item.href || pathname.startsWith(item.href + "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cx(
                "group flex items-center gap-3 rounded-xl px-3.5 py-2.5 text-sm font-medium transition-all duration-150",
                active
                  ? "bg-white/10 text-white shadow-[inset_2px_0_0_0_#34d399]"
                  : "text-slate-400 hover:bg-white/5 hover:text-white"
              )}
            >
              <Icon
                name={item.icon}
                className={cx("h-[18px] w-[18px] transition-colors", active ? "text-emerald-400" : "text-slate-500 group-hover:text-slate-300")}
              />
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="mx-3 mb-3 rounded-2xl bg-white/[0.04] p-3.5 ring-1 ring-white/[0.06]">
        <div className="flex items-center gap-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-emerald-400 to-emerald-600 text-xs font-bold text-[#0a1628]">
            {name.split(" ").map((w) => w[0]).slice(0, 2).join("").toUpperCase() || "U"}
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold text-white">{name}</div>
            <div className="truncate text-xs text-slate-500">{companyName}</div>
          </div>
          <span
            className={cx(
              "rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide",
              role === "ADMIN" ? "bg-emerald-500/20 text-emerald-300" : role === "HR" ? "bg-sky-500/20 text-sky-300" : "bg-slate-500/20 text-slate-400"
            )}
          >
            {role === "EMPLOYEE" ? "Staff" : role}
          </span>
        </div>
        <form action={logoutAction} className="mt-3">
          <button
            className="flex w-full items-center justify-center gap-2 rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-xs font-semibold text-slate-300 transition hover:bg-white/10 hover:text-white"
            type="submit"
          >
            <Icon name="logout" className="h-3.5 w-3.5" /> Sign out
          </button>
        </form>
      </div>
    </aside>
  );
}
