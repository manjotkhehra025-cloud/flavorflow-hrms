import { Pa } from "@/components/Pa";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Card, PageHeader, Badge } from "@/components/ui";
import { AvatarImg } from "@/components/AvatarImg";
import { PrintButton } from "@/components/PrintButton";
import { kraScoreOf, currentQuarter } from "@/lib/kra";
import Link from "next/link";

export const dynamic = "force-dynamic";

function mondayOf(d: Date): Date {
  const dt = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = dt.getUTCDay();
  const shift = day === 0 ? -6 : 1 - day;
  return new Date(dt.getTime() + shift * 86400000);
}
function addDays(d: Date, n: number) {
  return new Date(d.getTime() + n * 86400000);
}
function fmtD(d: Date) {
  return d.toLocaleDateString("en-IN", { day: "numeric", month: "short", timeZone: "UTC" });
}
function iso(d: Date) {
  return d.toISOString().slice(0, 10);
}

export default async function TopsPage({ searchParams }: { searchParams: Promise<{ w?: string }> }) {
  const me = await requireStaff();
  const { w } = await searchParams;

  const thisMonday = mondayOf(new Date());
  const start = w ? mondayOf(new Date(w + "T00:00:00Z")) : thisMonday;
  const end = addDays(start, 6);
  const isCurrentWeek = iso(start) === iso(thisMonday);
  const inFuture = start.getTime() > thisMonday.getTime();

  const employees = await db.employee.findMany({
    where: { companyId: me.companyId, status: "ACTIVE" },
    include: { department: true },
    orderBy: { firstName: "asc" },
  });

  const [attendance, otApproved, leaves, holidays] = await Promise.all([
    db.attendance.findMany({ where: { companyId: me.companyId, date: { gte: start, lte: end } } }),
    db.punchRequest.findMany({
      where: { companyId: me.companyId, type: "OT", status: "APPROVED", date: { gte: start, lte: end } },
      select: { employeeId: true, hours: true },
    }),
    db.leaveRequest.findMany({
      where: { companyId: me.companyId, status: "APPROVED", fromDate: { lte: end }, toDate: { gte: start } },
      select: { employeeId: true, fromDate: true, toDate: true },
    }),
    db.holiday.findMany({ where: { companyId: me.companyId, date: { gte: start, lte: end } }, select: { date: true } }),
  ]);

  const byEmp = new Map<string, { present: number; hours: number }>();
  for (const a of attendance) {
    const cur = byEmp.get(a.employeeId) ?? { present: 0, hours: 0 };
    if (a.checkIn) cur.present += 1;
    if (a.checkIn && a.checkOut) cur.hours += Math.max(0, (a.checkOut.getTime() - a.checkIn.getTime()) / 3600000);
    byEmp.set(a.employeeId, cur);
  }
  const otByEmp = new Map<string, number>();
  for (const o of otApproved) otByEmp.set(o.employeeId, (otByEmp.get(o.employeeId) ?? 0) + (o.hours ?? 0));

  // KRA: current quarter live scores (published cycles only)
  const qtr = currentQuarter(start);
  const kraGoals = await db.kraGoal.findMany({
    where: { cycle: { companyId: me.companyId, year: qtr.year, quarter: qtr.quarter, status: { not: "DRAFT" } } },
    select: { employeeId: true, weight: true, target: true, achieved: true },
  });
  const kraByEmp = new Map<string, { weight: number; target: number; achieved: number }[]>();
  for (const g of kraGoals) {
    const list = kraByEmp.get(g.employeeId) ?? [];
    list.push({ weight: g.weight, target: g.target, achieved: g.achieved });
    kraByEmp.set(g.employeeId, list);
  }

  const leaveDays = new Map<string, number>();
  const holidayDays = holidays.length;
  for (const l of leaves) {
    let days = 0;
    for (let d = new Date(Math.max(l.fromDate.getTime(), start.getTime())); d <= l.toDate && d <= end; d = addDays(d, 1)) days++;
    leaveDays.set(l.employeeId, (leaveDays.get(l.employeeId) ?? 0) + days);
  }

  const weekLabel = `Week 15–21 ${start.toLocaleDateString("en-IN", { month: "short", year: "numeric", timeZone: "UTC" })}`;
  const totalHours = [...byEmp.values()].reduce((s, v) => s + v.hours, 0);
  const vistaCols = employees.map((e) => ({
    e,
    present: byEmp.get(e.id)?.present ?? 0,
    hours: Math.round((byEmp.get(e.id)?.hours ?? 0) * 10) / 10,
    ot: otByEmp.get(e.id) ?? 0,
    leaves: leaveDays.get(e.id) ?? 0,
    kra: kraByEmp.has(e.id) ? kraScoreOf(kraByEmp.get(e.id)!).pct : null,
  }));

  return (
    <div className="print-area">
      <PageHeader title={<Pa>TOPS Weekly Overview</Pa>} subtitle={`Attend · OT · Leaves — ${weekLabel} (${fmtD(start)} to ${fmtD(end)})`} />

      {/* Week nav */}
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3 print:hidden">
        <div className="flex items-center gap-2">
          <Link href={`/tops?w=${iso(addDays(start, -7))}`} className="btn-ghost px-3 py-1.5 text-sm">{<Pa>‹ Prev week</Pa>}</Link>
          <Link href={`/tops?w=${iso(thisMonday)}`} className="btn-ghost px-3 py-1.5 text-sm disabled:opacity-40" aria-disabled={isCurrentWeek}>{<Pa>This week</Pa>}</Link>
          <Link href={`/tops?w=${iso(addDays(start, 7))}`} className="btn-ghost px-3 py-1.5 text-sm">{<Pa>Next ›</Pa>}</Link>
        </div>
        <PrintButton label={<Pa>Export PDF</Pa>} />
      </div>

      {/* Summary strip */}
      <Card className="mb-6 grid grid-cols-2 gap-4 border-l-4! border-l-emerald-500! p-5 sm:grid-cols-4">
        <div>
          <div className="text-xs font-bold uppercase tracking-wide text-slate-400">{<Pa>Team size</Pa>}</div>
          <div className="mt-1 text-2xl font-black text-slate-900">{employees.length}</div>
        </div>
        <div>
          <div className="text-xs font-bold uppercase tracking-wide text-slate-400">{<Pa>Total shifts logged</Pa>}</div>
          <div className="mt-1 text-2xl font-black text-emerald-600">{[...byEmp.values()].reduce((s, v) => s + v.present, 0)}</div>
        </div>
        <div>
          <div className="text-xs font-bold uppercase tracking-wide text-slate-400">{<Pa>Total hours</Pa>}</div>
          <div className="mt-1 text-2xl font-black text-slate-900">{totalHours.toFixed(1)}h</div>
        </div>
        <div>
          <div className="text-xs font-bold uppercase tracking-wide text-slate-400">{<Pa>OT approved</Pa>}</div>
          <div className="mt-1 text-2xl font-black text-emerald-600">{[...otByEmp.values()].reduce((a, b) => a + b, 0)}h</div>
        </div>
      </Card>

      {/* Main table */}
      <Card className="overflow-hidden">
        <div className="border-b border-slate-100 p-5 pb-4">
          <h3 className="text-sm font-bold text-slate-900">{weekLabel}</h3>
          <p className="text-xs text-slate-400">{<Pa>G.D. Foods Mfg. (I) Pvt. Ltd. · Factory workforce weekly sheet</Pa>}</p>
        </div>
        {vistaCols.length === 0 ? (
          <p className="p-6 text-sm text-slate-500">{<Pa>No employees yet.</Pa>}</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-100">
                  <th className="th">{<Pa>Employee</Pa>}</th>
                  <th className="th text-center">{<Pa>Present</Pa>}</th>
                  <th className="th text-center">{<Pa>Hours</Pa>}</th>
                  <th className="th text-center">{<Pa>OT</Pa>}</th>
                  <th className="th text-center">{<Pa>Leave</Pa>}</th>
                  <th className="th text-center">KRA Q{qtr.quarter}</th>
                  <th className="th text-center">{<Pa>Grade</Pa>}</th>
                </tr>
              </thead>
              <tbody>
                {vistaCols.map(({ e, present, hours, ot, leaves, kra }) => {
                  const maxWorkDays = 7 - holidayDays - 1; // week minus offs & holidays approximation
                  const score = Math.round((present / Math.max(maxWorkDays, 1)) * 100);
                  const PERF = score >= 90 ? { tone: "green" as const, chip: "Star" } : score >= 70 ? { tone: "blue" as const, chip: "Good" } : score >= 50 ? { tone: "amber" as const, chip: "Low" } : { tone: "red" as const, chip: "Poor" };
                  return (
                    <tr key={e.id} className="border-b border-slate-50 transition hover:bg-slate-50/60">
                      <td className="td">
                        <Link href={`/employees/${e.id}`} className="flex items-center gap-2.5 font-medium text-slate-800 hover:text-emerald-700">
                          <AvatarImg name={`${e.firstName} ${e.lastName}`} photoUrl={e.photoUrl} size="h-8 w-8" textSize="text-[10px]" />
                          <span>
                            {e.firstName} {e.lastName}
                            <span className="ml-1.5 text-[10px] font-medium text-slate-400">{e.department?.name ?? "—"}</span>
                          </span>
                        </Link>
                      </td>
                      <td className="td text-center tabular-nums font-bold text-slate-700">{present}</td>
                      <td className="td text-center tabular-nums text-slate-600">{hours}h</td>
                      <td className="td text-center tabular-nums">
                        {ot > 0 ? <span className="font-bold text-emerald-600">{ot}h</span> : <span className="text-slate-400">—</span>}
                      </td>
                      <td className="td text-center tabular-nums">
                        {leaves > 0 ? <span className="text-amber-600 font-semibold">{leaves}</span> : <span className="text-slate-400">—</span>}
                      </td>
                      <td className="td text-center">
                        {kra === null ? (
                          <span className="text-slate-300">—</span>
                        ) : (
                          <span className={`font-extrabold tabular-nums ${kra >= 75 ? "text-emerald-600" : kra >= 50 ? "text-amber-600" : "text-rose-500"}`}>
                            {kra}%
                          </span>
                        )}
                      </td>
                      <td className="td text-center">
                        <Badge tone={PERF.tone}>{score}%</Badge>
                        <span className="ml-1 text-[10px] font-semibold text-slate-500">{PERF.chip}</span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <div className="border-t border-slate-100 px-5 py-3 text-[11px] text-slate-400 print:block">
          <Pa>Star Performer auto-marked at ≥90% attendance · OT counts only approved requests · Generated via HRMate</Pa> {new Date().toLocaleDateString("en-IN")}
        </div>
      </Card>
    </div>
  );
}
