"use client";

import Link from "next/link";
import { Icon } from "./icons";
import { Tt } from "@/components/LangCtx";
import { timeAgo } from "@/lib/utils";

export type FeedItem = { at: string; actor: string; text: string; href: string; icon: "clock" | "leaf" | "badge" | "check" | "x" | "chat" };

export function ActivityFeed({ items }: { items: FeedItem[] }) {
  return (
    <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
      <header className="flex items-center justify-between border-b border-slate-100 px-4 py-3">
        <h3 className="text-sm font-extrabold text-slate-800">⚡ <Tt>Recent activity</Tt></h3>
        <Link href="/activity" className="text-xs font-semibold text-emerald-600 hover:underline"><Tt>View all →</Tt></Link>
      </header>
      <ul className="divide-y divide-slate-100">
        {items.map((a, i) => (
          <li key={i}>
            <Link href={a.href} className="flex items-start gap-3 px-4 py-2.5 transition hover:bg-emerald-50/40">
              <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500">
                <Icon name={a.icon} className="h-3.5 w-3.5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13px] text-slate-600"><b className="font-extrabold text-slate-800">{a.actor}</b> {a.text}</span>
              </span>
              <span className="ml-auto shrink-0 text-[11px] font-semibold text-slate-400">{timeAgo(a.at)}</span>
            </Link>
          </li>
        ))}
        {items.length === 0 && <li className="px-4 py-8 text-center text-sm text-slate-400"><Tt>All quiet for now. ✨</Tt></li>}
      </ul>
    </section>
  );
}
