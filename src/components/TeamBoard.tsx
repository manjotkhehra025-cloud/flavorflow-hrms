"use client";

import Link from "next/link";
import { useActionState } from "react";
import { AvatarImg } from "./AvatarImg";
import { Tt } from "@/components/LangCtx";
import { setWeeklyOffAction } from "@/actions/employees";
import { cx } from "@/lib/utils";

type Row = {
  id: string; name: string; dept: string; shift: string; photo: string | null;
  status: "IN" | "OUT" | "ABSENT"; inAt: string | null; outAt: string | null;
  completed: boolean; weeklyOff: number;
};
type Counts = { in: number; out: number; absent: number; done: number };

const CHIP: Record<Row["status"], { label: string; cls: string; dot: string }> = {
  IN: { label: "In", cls: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" },
  OUT: { label: "Out", cls: "bg-sky-100 text-sky-700", dot: "bg-sky-500" },
  ABSENT: { label: "Not in yet", cls: "bg-slate-100 text-slate-500", dot: "bg-slate-300" },
};

export function TeamBoard({ rows, counts, departments, activeDept, dayNames }: { rows: Row[]; counts: Counts; departments: { id: string; name: string }[]; activeDept: string; dayNames: string[] }) {
  return (
    <div className="space-y-4">
      {/* counters */}
      <div className="grid grid-cols-4 gap-2.5">
        {(
          [
            { n: counts.in, l: "Punched In", c: "text-emerald-600", bg: "bg-emerald-50 border-emerald-100" },
            { n: counts.out, l: "Punched Out", c: "text-sky-600", bg: "bg-sky-50 border-sky-100" },
            { n: counts.absent, l: "Not in yet", c: "text-slate-500", bg: "bg-slate-50 border-slate-100" },
            { n: counts.done, l: "Shift done", c: "text-violet-600", bg: "bg-violet-50 border-violet-100" },
          ] as const
        ).map((t) => (
          <div key={t.l} className={cx("rounded-2xl border p-3 text-center", t.bg)}>
            <p className={cx("text-2xl font-extrabold tabular-nums", t.c)}>{t.n}</p>
            <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400"><Tt>{t.l}</Tt></p>
          </div>
        ))}
      </div>

      {/* dept filter */}
      <div className="flex gap-1.5 overflow-x-auto pb-1">
        <Link href="/team" className={cx("whitespace-nowrap rounded-full px-3 py-1.5 text-xs font-bold transition", !activeDept ? "bg-[#0a1628] text-emerald-300" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}>
          <Tt>All Departments</Tt>
        </Link>
        {departments.map((d) => (
          <Link key={d.id} href={`/team?dept=${d.id}`} className={cx("whitespace-nowrap rounded-full px-3 py-1.5 text-xs font-bold transition", activeDept === d.id ? "bg-[#0a1628] text-emerald-300" : "bg-slate-100 text-slate-600 hover:bg-slate-200")}>
            {d.name}
          </Link>
        ))}
      </div>

      {/* rows */}
      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
        <ul className="divide-y divide-slate-100">
          {rows.map((r) => {
            const chip = CHIP[r.status];
            return (
              <li key={r.id} className="flex items-center gap-3 px-4 py-3">
                <div className="relative shrink-0">
                  <AvatarImg name={r.name} photoUrl={r.photo} size="h-10 w-10" />
                  <span className={cx("absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full ring-2 ring-white", chip.dot)} />
                </div>
                <div className="min-w-0 flex-1">
                  <Link href={`/employees/${r.id}`} className="block truncate text-sm font-extrabold text-slate-800 hover:text-emerald-700">{r.name}</Link>
                  <p className="truncate text-xs text-slate-500">{r.dept} · {r.shift}</p>
                </div>
                <div className="hidden text-right text-[11px] font-semibold text-slate-500 sm:block">
                  {r.inAt && <div>IN {r.inAt}</div>}
                  {r.outAt && <div>OUT {r.outAt}</div>}
                </div>
                <span className={cx("hidden whitespace-nowrap rounded-full px-2.5 py-1 text-[11px] font-extrabold sm:inline-block", chip.cls)}><Tt>{chip.label}</Tt></span>
                {r.completed && <span className="hidden whitespace-nowrap rounded-full bg-violet-100 px-2.5 py-1 text-[11px] font-extrabold text-violet-700 sm:inline-block">✔ <Tt>Done</Tt></span>}
                <WeeklyOffSelect empId={r.id} value={r.weeklyOff} dayNames={dayNames} />
              </li>
            );
          })}
          {rows.length === 0 && <li className="px-4 py-10 text-center text-sm text-slate-400"><Tt>No employees in this filter.</Tt></li>}
        </ul>
      </div>
    </div>
  );
}

function WeeklyOffSelect({ empId, value, dayNames }: { empId: string; value: number; dayNames: string[] }) {
  const [state, formAction, pending] = useActionState(setWeeklyOffAction, {});
  // The shared action expects many fields; we only blame missing ones as optional — it uses updateMany with provided fields.
  return (
    <form action={formAction} className="shrink-0">
      <input type="hidden" name="employeeId" value={empId} />
      <select
        name="weeklyOff"
        defaultValue={value}
        disabled={pending}
        onChange={(e) => e.currentTarget.form?.requestSubmit()}
        className="rounded-lg bg-amber-50 px-2 py-1.5 text-[11px] font-bold text-amber-700 ring-1 ring-inset ring-amber-200 outline-none"
        aria-label="Weekly off"
      >
        {dayNames.map((d, i) => (
          <option key={d} value={i}>{d.slice(0, 3)} off</option>
        ))}
      </select>
    </form>
  );
}
