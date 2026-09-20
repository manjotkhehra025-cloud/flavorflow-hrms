"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cx } from "@/lib/utils";
import { Icon } from "./icons";
import { navFor } from "./Sidebar";

export function MobileTopBar({ companyName, userName }: { companyName: string; userName: string }) {
  return (
    <div className="fixed inset-x-0 top-0 z-30 flex items-center justify-between border-b border-white/[0.06] bg-slate-950/95 px-4 py-3 backdrop-blur md:hidden">
      <div className="flex items-center gap-2.5">
        <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-gradient-to-br from-amber-400 to-amber-600 text-xs font-black text-slate-950">
          FF
        </div>
        <span className="max-w-[55vw] truncate text-sm font-bold text-white">{companyName}</span>
      </div>
      <span className="flex h-8 w-8 items-center justify-center rounded-full bg-white/10 text-xs font-bold text-amber-400">
        {userName[0]?.toUpperCase()}
      </span>
    </div>
  );
}

export function MobileBottomNav({ role }: { role: string }) {
  const pathname = usePathname();
  const items = navFor(role);

  return (
    <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-slate-200/70 bg-white/95 pb-[env(safe-area-inset-bottom)] backdrop-blur md:hidden">
      <div className="mx-auto flex max-w-md items-stretch justify-between px-1">
        {items.map((item) => {
          const active = pathname === item.href || pathname.startsWith(item.href + "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cx(
                "flex flex-1 flex-col items-center gap-1 py-2 text-[10px] font-semibold transition-colors",
                active ? "text-amber-600" : "text-slate-400"
              )}
            >
              <span className={cx(
                "flex h-8 w-14 items-center justify-center rounded-full transition-colors",
                active && "bg-amber-500/15"
              )}>
                <Icon name={item.icon} className="h-[19px] w-[19px]" />
              </span>
              {item.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
