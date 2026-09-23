import { db } from "@/lib/db";
import { monthRange } from "@/lib/reports";

export type EmpStat = {
  employeeId: string; code: string; name: string; dept: string;
  present: number; late: number; half: number; absent: number; workedH: number; lateMin: number;
};
export type DeptStat = { dept: string; pct: number; n: number };
export type MonthAnalytics = {
  present: number; late: number; half: number; absent: number; onTimePct: number; avgLateMin: number;
  perEmp: EmpStat[]; byDept: DeptStat[]; daysWithData: number;
};

function istMinutes(d: Date): number { const t = new Date(d.getTime() + 330 * 60000); return t.getUTCHours() * 60 + t.getUTCMinutes(); }

/** Month analytics: tiles, dept bars, on-time %, per-employee rows. */
export async function buildMonthAnalytics(companyId: string, month: string): Promise<MonthAnalytics> {
  const { start, endExclusive } = monthRange(month);
  const today = new Date();
  const cap = new Date(Math.min(endExclusive.getTime() - 1, Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate())));

  const [employees, attendance, holidays, leaves] = await Promise.all([
    db.employee.findMany({ where: { companyId, status: "ACTIVE" }, include: { department: true, shift: true } }),
    db.attendance.findMany({ where: { companyId, date: { gte: start, lt: endExclusive } } }),
    db.holiday.findMany({ where: { companyId, date: { gte: start, lt: endExclusive } }, select: { date: true } }),
    db.leaveRequest.findMany({ where: { companyId, status: "APPROVED", fromDate: { lt: endExclusive }, toDate: { gte: start } } }),
  ]);

  const holidaySet = new Set(holidays.map((h) => h.date.toISOString().slice(0, 10)));
  const leaveDays = new Set<string>(); // emp|date
  for (const l of leaves) {
    for (let d = new Date(l.fromDate); d <= l.toDate; d = new Date(d.getTime() + 86400000)) {
      if (d >= start && d < endExclusive) leaveDays.add(`${l.employeeId}|${d.toISOString().slice(0, 10)}`);
    }
  }
  const attByEmp = new Map<string, Map<string, typeof attendance[number]>>();
  for (const a of attendance) {
    const iso = a.date.toISOString().slice(0, 10);
    if (!attByEmp.has(a.employeeId)) attByEmp.set(a.employeeId, new Map());
    attByEmp.get(a.employeeId)!.set(iso, a);
  }

  const GRACE = 10;
  let totPresent = 0, totLate = 0, totHalf = 0, totAbsent = 0, onTime = 0, lateMinsAll: number[] = [];
  const perEmp: EmpStat[] = [];
  const byDeptRows = new Map<string, { p: number; d: number }>();

  for (let day = new Date(start); day <= cap; day = new Date(day.getTime() + 86400000)) {
    const iso = day.toISOString().slice(0, 10);
    if (holidaySet.has(iso)) continue;
    for (const e of employees) {
      if (day.getUTCDay() === e.weeklyOff) continue;
      const dept = e.department?.name ?? "General";
      if (!byDeptRows.has(dept)) byDeptRows.set(dept, { p: 0, d: 0 });
      byDeptRows.get(dept)!.d++;
      const stat = perEmp.find((r) => r.employeeId === e.id) ?? (() => {
        const row: EmpStat = { employeeId: e.id, code: e.code, name: `${e.firstName} ${e.lastName ?? ""}`.trim(), dept, present: 0, late: 0, half: 0, absent: 0, workedH: 0, lateMin: 0 };
        perEmp.push(row); return row;
      })();
      const a = attByEmp.get(e.id)?.get(iso);
      if (a?.checkIn) {
        const shiftStart = e.shift?.startTime ?? "08:00";
        const [sh, sm] = shiftStart.split(":").map(Number);
        const inMin = istMinutes(a.checkIn);
        const late = Math.max(0, inMin - (sh * 60 + sm) - GRACE);
        const worked = a.checkOut ? (a.checkOut.getTime() - a.checkIn.getTime()) / 3600000 : 0;
        const isHalf = a.status === "HALF_DAY" || (worked > 0 && worked < 5.5);
        stat.workedH += worked;
        if (isHalf) { stat.half++; totHalf++; }
        else { stat.present++; totPresent++; }
        if (late > 0) { stat.late++; stat.lateMin += late; totLate++; lateMinsAll.push(late); } else if (!isHalf) onTime++;
        if (!isHalf) byDeptRows.get(dept)!.p++; else byDeptRows.get(dept)!.p += 0.5;
      } else if (!leaveDays.has(`${e.id}|${iso}`) && a?.status !== "HOLIDAY" && a?.status !== "LEAVE") {
        stat.absent++; totAbsent++;
      } else if (leaveDays.has(`${e.id}|${iso}`)) {
        byDeptRows.get(dept)!.p++; // approved leave counts as covered for pct purposes
      }
    }
  }

  const byDept: DeptStat[] = [...byDeptRows.entries()].map(([dept, v]) => ({ dept, n: Math.round(v.p), pct: v.d ? Math.round((v.p / v.d) * 100) : 0 })).sort((a, b) => b.pct - a.pct);
  perEmp.sort((a, b) => b.present - a.present || b.workedH - a.workedH);

  // distinct punch days = sparkline denominator
  const daysWithData = new Set(attendance.map((a) => a.date.toISOString().slice(0, 10))).size;
  return {
    present: totPresent, late: totLate, half: totHalf, absent: totAbsent,
    onTimePct: totPresent > 0 ? Math.round((onTime / totPresent) * 100) : 100,
    avgLateMin: lateMinsAll.length ? Math.round(lateMinsAll.reduce((a, b) => a + b, 0) / lateMinsAll.length) : 0,
    perEmp, byDept, daysWithData,
  };
}

/** Per-day punch counts for a tiny sparkline (day number → punches). */
export function sparklineFromAxis(daysInMonth: number, counts: number[]): string {
  const max = Math.max(1, ...counts);
  const pts = counts.map((c, i) => `${(i + 0.5) * (120 / daysInMonth)},${18 - (c / max) * 16}`).join(" ");
  return pts;
}
