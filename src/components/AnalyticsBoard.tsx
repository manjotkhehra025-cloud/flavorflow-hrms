"use client";

import { useMemo, useState } from "react";
import { Tt } from "@/components/LangCtx";
import { cx } from "@/lib/utils";

export type AnalyticsUi = {
  month: string;
  label: string;
  tiles: { present: number; late: number; half: number; absent: number; onTimePct: number; avgLateMin: number };
  byDept: { dept: string; pct: number; n: number }[];
  sparkline: number[];
  rows: { employeeId: string; code: string; name: string; dept: string; present: number; late: number; half: number; absent: number; workedH: number; lateMin: number }[];
};

function toCSV(rows: AnalyticsUi["rows"], label: string): string {
  const head = "Code,Employee,Dept,Present,Half-day,Late-days,Late-mins,Absent,Worked-hrs";
  const lines = rows.map((r) => [r.code, `"${r.name}"`, r.dept, r.present, r.half, r.late, r.lateMin, r.absent, r.workedH].join(","));
  return [head, ...lines].join("\n");
}

export function AnalyticsBoard({ data }: { data: AnalyticsUi }) {
  const [q, setQ] = useState("");
  const rows = useMemo(
    () => data.rows.filter((r) => !q || r.name.toLowerCase().includes(q.toLowerCase()) || r.code.toLowerCase().includes(q.toLowerCase()) || r.dept.toLowerCase().includes(q.toLowerCase())),
    [data.rows, q]
  );
  const sparkMax = Math.max(1, ...data.sparkline);

  const tiles = [
    { n: data.tiles.present, l: "Present+duty", c: "text-emerald-600", bg: "bg-emerald-50 border-emerald-100", icon: "🟢" },
    { n: data.tiles.late, l: "Late marks", c: "text-rose-600", bg: "bg-rose-50 border-rose-100", icon: "⏰" },
    { n: data.tiles.half, l: "Half-days", c: "text-amber-600", bg: "bg-amber-50 border-amber-100", icon: "🌗" },
    { n: data.tiles.absent, l: "Absents", c: "text-slate-500", bg: "bg-slate-50 border-slate-100", icon: "⛔" },
  ];

  function downloadCsv() {
    const blob = new Blob([toCSV(rows, data.label)], { type: "text/csv" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `attendance-analytics-${data.month}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  return (
    <section className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm">
      <header className="border-b border-slate-100 bg-gradient-to-r from-[#0a1628] to-[#102b42] px-5 py-4 text-white">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-base font-extrabold tracking-tight">📊 <Tt>Attendance analytics</Tt></h2>
            <p className="text-[11px] font-semibold text-slate-400">{data.label} — <Tt>punch-ins counted till today</Tt></p>
          </div>
          <div className="flex items-center gap-2">
            <button type="button" onClick={downloadCsv} className="rounded-xl bg-emerald-500 px-3 py-1.5 text-xs font-extrabold text-white shadow transition hover:brightness-110">⬇ <Tt>CSV</Tt></button>
            <button type="button" onClick={() => window.print()} className="rounded-xl bg-white/10 px-3 py-1.5 text-xs font-extrabold text-slate-200 ring-1 ring-white/20 transition hover:bg-white/15">🖨 <Tt>Print</Tt></button>
          </div>
        </div>
        {/* sparkline of daily punch-ins */}
        <svg viewBox="0 0 120 20" preserveAspectRatio="none" className="mt-3 h-8 w-full opacity-80">
          <polyline fill="none" stroke="#34d399" strokeWidth="1.2" points={data.sparkline.map((c, i) => `${((i + 0.5) * 120) / data.sparkline.length},${18 - (c / sparkMax) * 15}`).join(" ")} />
        </svg>
      </header>

      {/* tiles */}
      <div className="grid grid-cols-2 gap-2.5 p-4 sm:grid-cols-6">
        {tiles.map((t) => (
          <div key={t.l} className={cx("rounded-2xl border p-3", t.bg)}>
            <p className={cx("text-xl font-extrabold tabular-nums", t.c)}>{t.icon} {t.n}</p>
            <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400"><Tt>{t.l}</Tt></p>
          </div>
        ))}
        <div className="rounded-2xl border border-violet-100 bg-violet-50 p-3">
          <p className="text-xl font-extrabold tabular-nums text-violet-600">{data.tiles.onTimePct}%</p>
          <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400"><Tt>On-time rate</Tt></p>
        </div>
        <div className="rounded-2xl border border-sky-100 bg-sky-50 p-3">
          <p className="text-xl font-extrabold tabular-nums text-sky-600">{data.tiles.avgLateMin}<span className="text-xs">m</span></p>
          <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400"><Tt>Avg late delay</Tt></p>
        </div>
      </div>

      <div className="grid gap-4 px-4 pb-4 lg:grid-cols-5">
        {/* dept bars */}
        <div className="rounded-2xl bg-slate-50 p-4 lg:col-span-2">
          <h3 className="mb-2 text-[11px] font-extrabold uppercase tracking-wide text-slate-400"><Tt>Department strength %</Tt></h3>
          {data.byDept.length === 0 && <p className="text-xs text-slate-400"><Tt>No punches yet this month.</Tt></p>}
          <div className="space-y-2">
            {data.byDept.map((d) => (
              <div key={d.dept}>
                <div className="flex items-center justify-between text-[11px] font-bold text-slate-600">
                  <span className="truncate">{d.dept}</span>
                  <span className="tabular-nums text-slate-400">{d.pct}%</span>
                </div>
                <div className="mt-0.5 h-2 overflow-hidden rounded-full bg-slate-200">
                  <div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-emerald-600" style={{ width: `${Math.max(3, d.pct)}%` }} />
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* per-employee table */}
        <div className="lg:col-span-3">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search employee / dept…"
            className="mb-2 w-full rounded-xl bg-slate-50 px-3.5 py-2 text-xs outline-none ring-1 ring-inset ring-slate-200 focus:ring-2 focus:ring-emerald-400"
          />
          <div className="max-h-72 overflow-y-auto rounded-2xl ring-1 ring-slate-100">
            <table className="w-full text-left text-xs">
              <thead className="sticky top-0 bg-slate-50 text-[10px] font-extrabold uppercase tracking-wide text-slate-400">
                <tr>
                  <th className="px-3 py-2"><Tt>Employee</Tt></th>
                  <th className="px-2 py-2 text-center">P</th>
                  <th className="px-2 py-2 text-center">½</th>
                  <th className="px-2 py-2 text-center"><Tt>Late</Tt></th>
                  <th className="px-2 py-2 text-center">Absent</th>
                  <th className="px-2 py-2 text-center"><Tt>Hrs</Tt></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-50">
                {rows.map((r) => (
                  <tr key={r.employeeId} className="hover:bg-emerald-50/40">
                    <td className="px-3 py-2"><span className="font-bold text-slate-700">{r.name}</span> <span className="text-[10px] text-slate-400">· {r.dept}</span></td>
                    <td className="px-2 py-2 text-center font-bold tabular-nums text-emerald-600">{r.present}</td>
                    <td className="px-2 py-2 text-center tabular-nums text-amber-600">{r.half || ""}</td>
                    <td className="px-2 py-2 text-center tabular-nums text-rose-500">{r.late || ""}</td>
                    <td className="px-2 py-2 text-center tabular-nums text-slate-500">{r.absent || ""}</td>
                    <td className="px-2 py-2 text-center tabular-nums text-slate-600">{r.workedH}</td>
                  </tr>
                ))}
                {rows.length === 0 && (
                  <tr><td colSpan={6} className="px-3 py-8 text-center text-slate-400"><Tt>Nothing matches your search.</Tt></td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
}
