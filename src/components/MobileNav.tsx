"use client";
import { LangToggle } from "./LangToggle";
import { Tt } from "@/components/LangCtx";

import Link from "next/link";
import { useState } from "react";
import { usePathname } from "next/navigation";
import { Icon } from "./icons";
import { HLogo } from "./Sidebar";
import { logoutAction } from "@/actions/auth";
import { cx } from "@/lib/utils";

export function MobileTopBar({ name }: { name: string }) {
  return (
    <header className="fixed inset-x-0 top-0 z-40 flex h-14 items-center justify-between border-b border-white/[0.06] bg-[#0a1628] px-4 lg:hidden">
      <div className="flex items-center gap-2.5">
        <HLogo className="h-8 w-8" />
        <div className="leading-tight">
          <span className="block text-sm font-extrabold tracking-tight text-white">{<Tt>HRMate</Tt>}</span>
          <span className="block text-[10px] text-emerald-400/80"><Tt>Sat Sri Akal</Tt>, {name.split(" ")[0]} 🙏</span>
        </div>
      </div>
      <LangToggle dark />
    </header>
  );
}

const MORE_ITEMS: { href: string; label: string; icon: Parameters<typeof Icon>[0]["name"]; staffOnly?: boolean }[] = [
  { href: "/attendance", label: "Attendance & Logs", icon: "clock" },
  { href: "/employees", label: "Team", icon: "users", staffOnly: true },
  { href: "/idcard", label: "ID Card & Gate Pass", icon: "badge" },
  { href: "/approvals", label: "Approvals", icon: "check", staffOnly: true },
  { href: "/holidays", label: "Holidays", icon: "calendar" },
  { href: "/departments", label: "Org Structure", icon: "building", staffOnly: true },
  { href: "/reports", label: "Reports", icon: "report", staffOnly: true },
  { href: "/tops", label: "TOPS Weekly", icon: "chart", staffOnly: true },
  { href: "/kra", label: "KRA", icon: "target" },
  { href: "/helpdesk", label: "Helpdesk", icon: "chat" },
  { href: "/star", label: "Star ⭐", icon: "star", staffOnly: true },
  { href: "/settings", label: "Settings & Shifts", icon: "sliders", staffOnly: true },
];

export function MobileBottomNav({ employeeId, role }: { employeeId: string | null; role: string }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const staff = role !== "EMPLOYEE";
  const items = MORE_ITEMS.filter((i) => !i.staffOnly || staff);

  function Slot({ href, label, icon }: { href: string; label: string; icon: Parameters<typeof Icon>[0]["name"] }) {
    const active = pathname === href || pathname.startsWith(href + "/");
    return (
      <Link
        href={href}
        className={cx(
          "flex flex-1 flex-col items-center gap-0.5 py-2 text-[10px] font-semibold transition-colors",
          active ? "text-emerald-600" : "text-slate-400"
        )}
      >
        <Icon name={icon} className="h-5 w-5" />
        <Tt>{label}</Tt>
      </Link>
    );
  }

  return (
    <>
      {/* More sheet */}
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={() => setOpen(false)} />
          <div className="absolute inset-x-0 bottom-0 rounded-t-3xl bg-white p-4 pb-8 shadow-2xl animate-fade-up">
            <div className="mx-auto mb-3 h-1 w-10 rounded-full bg-slate-200" />
            <div className="grid grid-cols-3 gap-2">
              {items.map((i) => (
                <Link
                  key={i.href}
                  href={i.href}
                  onClick={() => setOpen(false)}
                  className="flex flex-col items-center gap-1.5 rounded-2xl bg-slate-50 px-2 py-3.5 text-center active:bg-slate-100"
                >
                  <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#0a1628] text-emerald-400">
                    <Icon name={i.icon} className="h-4.5 w-4.5" />
                  </span>
                  <span className="text-[11px] font-semibold leading-tight text-slate-700"><Tt>{i.label}</Tt></span>
                </Link>
              ))}
              <form action={logoutAction} className="contents">
                <button className="flex flex-col items-center gap-1.5 rounded-2xl bg-red-50 px-2 py-3.5 text-center active:bg-red-100">
                  <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-red-500/10 text-red-500">
                    <Icon name="logout" className="h-4.5 w-4.5" />
                  </span>
                  <span className="text-[11px] font-semibold text-red-600">{<Tt>Sign out</Tt>}</span>
                </button>
              </form>
            </div>
          </div>
        </div>
      )}

      {/* Bottom nav with center punch FAB */}
      <nav className="fixed bottom-0 left-0 right-0 z-30 border-t border-slate-200/80 bg-white/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-lg lg:hidden">
        <div className="flex items-stretch">
          <Slot href="/dashboard" label="Home" icon="home" />
          <Slot href="/leaves" label="Leaves" icon="leaf" />

          {employeeId ? (
            <Link
              href="/dashboard"
              className="relative flex w-16 flex-col items-center justify-center"
              aria-label="Punch"
            >
              <span className="-mt-6 flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-emerald-400 to-emerald-600 text-white shadow-[0_8px_20px_-4px_rgb(16_185_129_/_60%)] ring-4 ring-white active:scale-95 transition-all">
                <Icon name="fingerprint" className="h-7 w-7" />
              </span>
              <span className="mt-0.5 text-[10px] font-bold text-emerald-700">{<Tt>Punch</Tt>}</span>
            </Link>
          ) : (
            <div className="w-16" />
          )}

          <Slot href={staff ? "/approvals" : "/idcard"} label={staff ? "Approvals" : "My ID"} icon={staff ? "check" : "badge"} />
          <button
            onClick={() => setOpen(true)}
            className={cx(
              "flex flex-1 flex-col items-center gap-0.5 py-2 text-[10px] font-semibold transition-colors",
              open ? "text-emerald-600" : "text-slate-400"
            )}
          >
            <Icon name="dots" className="h-5 w-5" />
            <Tt>More</Tt>
          </button>
        </div>
      </nav>
    </>
  );
}
