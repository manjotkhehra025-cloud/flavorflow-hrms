import { db } from "./db";

/** "2026-09" → { start, endExclusive, label } — dates are @db.Date (UTC). */
export function monthRange(month: string) {
  const [y, m] = month.split("-").map(Number);
  if (!y || !m || m < 1 || m > 12) return monthRange(currentMonth());
  return {
    start: new Date(Date.UTC(y, m - 1, 1)),
    endExclusive: new Date(Date.UTC(y, m, 1)),
    label: new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString("en-IN", { month: "long", year: "numeric", timeZone: "UTC" }),
  };
}

export function currentMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

export function shiftMonth(month: string, delta: number): string {
  const [y, m] = month.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

export type AttendanceRow = {
  code: string;
  name: string;
  department: string | null;
  present: number;
  fullDays: number; // days with both in & out
  leaveDays: number; // approved leave days overlapping the month
  totalHours: number;
  avgInMins: number | null; // minutes past midnight of average check-in
};

function minsSinceMidnight(d: Date): number {
  return d.getHours() * 60 + d.getMinutes();
}

function fmtHrs(h: number): string {
  return (Math.round(h * 10) / 10).toFixed(1);
}

export function fmtAvgTime(mins: number | null): string {
  if (mins === null) return "—";
  const h24 = Math.floor(mins / 60);
  const m = Math.round(mins % 60);
  const ampm = h24 >= 12 ? "PM" : "AM";
  const h = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h}:${String(m).padStart(2, "0")} ${ampm}`;
}

export async function buildMonthlyAttendance(companyId: string, month: string): Promise<AttendanceRow[]> {
  const { start, endExclusive } = monthRange(month);

  const [employees, attendance, leaves] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true },
      orderBy: [{ department: { name: "asc" } }, { firstName: "asc" }],
    }),
    db.attendance.findMany({
      where: { companyId, date: { gte: start, lt: endExclusive } },
    }),
    db.leaveRequest.findMany({
      where: {
        companyId,
        status: "APPROVED" as const,
        fromDate: { lt: endExclusive },
        toDate: { gte: start },
      },
      select: { employeeId: true, fromDate: true, toDate: true },
    }),
  ]);

  const byEmpAttendance = new Map<string, typeof attendance>();
  for (const a of attendance) {
    const list = byEmpAttendance.get(a.employeeId) ?? [];
    list.push(a);
    byEmpAttendance.set(a.employeeId, list);
  }
  const byEmpLeaves = new Map<string, typeof leaves>();
  for (const l of leaves) {
    const list = byEmpLeaves.get(l.employeeId) ?? [];
    list.push(l);
    byEmpLeaves.set(l.employeeId, list);
  }

  return employees.map((e) => {
    const rows = byEmpAttendance.get(e.id) ?? [];
    const present = rows.length;
    const fullRows = rows.filter((r) => r.checkIn && r.checkOut);
    const totalHours = fullRows.reduce(
      (sum, r) => sum + (r.checkOut!.getTime() - r.checkIn!.getTime()) / 3600000,
      0
    );
    const inMins = rows.filter((r) => r.checkIn).map((r) => minsSinceMidnight(r.checkIn!));
    const avgInMins = inMins.length ? inMins.reduce((a, b) => a + b, 0) / inMins.length : null;

    const leaveDays = (byEmpLeaves.get(e.id) ?? []).reduce((sum, l) => {
      const from = l.fromDate > start ? l.fromDate : start;
      const to = l.toDate < endExclusive ? l.toDate : endExclusive;
      return sum + Math.max(0, Math.floor((to.getTime() - from.getTime()) / 86400000) + (l.toDate < endExclusive ? 1 : 0));
    }, 0);

    return {
      code: e.code,
      name: `${e.firstName} ${e.lastName}`,
      department: e.department?.name ?? null,
      present,
      fullDays: fullRows.length,
      leaveDays,
      totalHours,
      avgInMins,
    };
  });
}

export function toCsv(rows: AttendanceRow[], monthLabel: string): string {
  const esc = (v: string | number) => {
    const s = String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const header = ["Code", "Name", "Department", "Days Present", "Full Days (In+Out)", "Leave Days", "Total Hours", "Avg Check-in"];
  const lines = [
    [`Attendance Report - ${monthLabel}`],
    header,
    ...rows.map((r) => [
      r.code,
      r.name,
      r.department ?? "",
      r.present,
      r.fullDays,
      r.leaveDays,
      fmtHrs(r.totalHours),
      fmtAvgTime(r.avgInMins),
    ]),
  ];
  return lines.map((line) => line.map(esc).join(",")).join("\r\n");
}
