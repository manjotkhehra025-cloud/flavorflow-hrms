"use client";
import { LangToggle } from "./LangToggle";
import { Tt } from "@/components/LangCtx";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon } from "./icons";
import { logoutAction } from "@/actions/auth";
import { cx } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/dashboard", label: "Dashboard", icon: "home" as const },
  { href: "/social", label: "Social Wall", icon: "chat" as const },
  { href: "/employees", label: "Employees", icon: "users" as const, staffOnly: true },
  { href: "/team", label: "Live Team", icon: "fingerprint" as const, staffOnly: true },
  { href: "/attendance", label: "Attendance", icon: "clock" as const },
  { href: "/leaves", label: "Leaves", icon: "leaf" as const },
  { href: "/approvals", label: "Approvals", icon: "check" as const, staffOnly: true, approverOk: true },
  { href: "/payroll", label: "Payroll", icon: "wallet" as const, staffOnly: true },
  { href: "/roster", label: "Roster", icon: "calendar" as const, staffOnly: true },
  { href: "/idcard", label: "ID Card & Gate Pass", icon: "badge" as const },
  { href: "/holidays", label: "Holidays", icon: "calendar" as const },
  { href: "/departments", label: "Departments", icon: "building" as const, staffOnly: true },
  { href: "/reports", label: "Reports", icon: "report" as const, staffOnly: true },
  { href: "/tops", label: "TOPS Weekly", icon: "chart" as const, staffOnly: true },
  { href: "/kra", label: "KRA", icon: "target" as const },
  { href: "/helpdesk", label: "Helpdesk", icon: "chat" as const },
  { href: "/payslips", label: "Payslips", icon: "wallet" as const },
  { href: "/star", label: "Employee of the Month", icon: "star" as const, staffOnly: true },
  { href: "/settings", label: "Settings", icon: "sliders" as const, staffOnly: true },
];

export function HLogo({ className = "h-10 w-10" }: { className?: string }) {
  // HRMate brand mark (approved D-var-1 artwork — exact file, no recreation)
  // eslint-disable-next-line @next/next/no-img-element
  return <img src="/hrmate-emblem.png" alt="HRMate" className={className} />;
}

export function Sidebar({ role, name, companyName, canApprove = false }: { role: string; name: string; companyName: string; canApprove?: boolean }) {
  const pathname = usePathname();
  const items = NAV_ITEMS.filter(
    (i) => role !== "EMPLOYEE" || !i.staffOnly || ((i as { approverOk?: boolean }).approverOk === true && canApprove),
  );

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
              <Tt>{item.label}</Tt>
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
            <Icon name="logout" className="h-3.5 w-3.5" /> <Tt>Sign out</Tt>
          </button>
        </form>
        <div className="mt-3 flex justify-center">
          <LangToggle dark />
        </div>
      </div>
    </aside>
  );
}
