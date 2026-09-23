"use client";

import { useState } from "react";
import Link from "next/link";
import { Icon } from "./icons";
import { Tt } from "@/components/LangCtx";
import { timeAgo, cx } from "@/lib/utils";

export type AlertUi = { kind: "leaf" | "clock" | "badge" | "calendar" | "check" | "x"; title: string; body: string; href: string; at: string | null };

export function AlertsBell({ count, items, dark = false }: { count: number; items: AlertUi[]; dark?: boolean }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <button
        type="button"
        aria-label="Notifications"
        onClick={() => setOpen((v) => !v)}
        className={cx(
          "relative flex h-9 w-9 items-center justify-center rounded-xl transition-colors",
          dark ? "bg-white/[0.07] text-slate-200 hover:bg-white/[0.12]" : "bg-slate-100 text-slate-600 hover:bg-slate-200"
        )}
      >
        <Icon name="bell" className="h-5 w-5" />
        {count > 0 && (
          <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-rose-500 px-1 text-[9px] font-extrabold text-white shadow">
            {count > 9 ? "9+" : count}
          </span>
        )}
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 z-50 mt-2 w-[19rem] overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl animate-fade-up sm:w-80">
            <div className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-4 py-2.5">
              <span className="text-sm font-extrabold text-slate-800"><Tt>Notifications</Tt></span>
              {count > 0 && <span className="rounded-full bg-rose-100 px-2 py-0.5 text-[10px] font-bold text-rose-600">{count} <Tt>new</Tt></span>}
            </div>
            <div className="max-h-96 divide-y divide-slate-50 overflow-y-auto">
              {items.length === 0 && (
                <p className="py-8 text-center text-xs text-slate-400"><Tt>All clear — nothing pending ✅</Tt></p>
              )}
              {items.map((a, i) => (
                <Link key={i} href={a.href} onClick={() => setOpen(false)} className="flex items-start gap-3 px-4 py-3 transition-colors hover:bg-emerald-50/50">
                  <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[#0a1628] text-emerald-400">
                    <Icon name={a.kind} className="h-4 w-4" />
                  </span>
                  <span className="min-w-0">
                    <span className="block truncate text-[13px] font-bold text-slate-700">{a.title}</span>
                    <span className="block truncate text-xs text-slate-500">{a.body}</span>
                    {a.at && <span className="mt-0.5 block text-[10px] font-semibold text-slate-400">{timeAgo(a.at)}</span>}
                  </span>
                </Link>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
