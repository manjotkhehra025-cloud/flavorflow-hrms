import { db } from "./db";
import { monthRange } from "./reports";
import { getLeaveBalances } from "./balances";

/** Factory-local (Asia/Kolkata, UTC+5:30) helpers — all report logic runs against factory wall-clock time. */
const IST_OFFSET_MS = 5.5 * 3600000;

/** UTC DateTime → minutes past midnight in factory wall-clock. */
export function istMins(d: Date): number {
  const t = new Date(d.getTime() + IST_OFFSET_MS);
  return t.getUTCHours() * 60 + t.getUTCMinutes();
}

export function minsToHHMM(mins: number): string {
  const h = Math.floor(mins / 60);
  const m = Math.round(mins % 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export function hoursFmt(h: number): string {
  return (Math.round(h * 10) / 10).toFixed(1);
}

/** Minutes of lateness before it stops counting as "late" (factory grace). */
export const LATE_GRACE_MINS = 10;

// ---------------------------------------------------------------------------
// 1) Monthly attendance register — employees × days grid
// ---------------------------------------------------------------------------

/** Register cell codes: P present · A absent · L leave · W weekly off · H holiday · "" n/a (future / pre-join) */
export type CellCode = "P" | "A" | "L" | "W" | "H" | "";

export type RegisterCell = { code: CellCode; inAt?: string; note?: string };

export type RegisterRow = {
  employeeId: string;
  code: string;
  name: string;
  department: string | null;
  cells: RegisterCell[]; // index 0 = day 1
  present: number;
  absent: number;
  leave: number;
  weeklyOff: number;
};

export type RegisterGrid = {
  month: string;
  label: string;
  daysInMonth: number;
  sundays: boolean[]; // per-day: employee-neutral info kept for header shading
  rows: RegisterRow[];
};

export async function buildRegisterGrid(companyId: string, month: string): Promise<RegisterGrid> {
  const { start, endExclusive, label } = monthRange(month);
  const daysInMonth = Math.round((endExclusive.getTime() - start.getTime()) / 86400000);
  const today = new Date();
  const todayUtcMid = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());

  const [employees, attendance, leaves, holidays] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true },
      orderBy: [{ firstName: "asc" }],
    }),
    db.attendance.findMany({
      where: { companyId, date: { gte: start, lt: endExclusive } },
      select: { employeeId: true, date: true, checkIn: true },
    }),
    db.leaveRequest.findMany({
      where: {
        companyId,
        status: "APPROVED",
        fromDate: { lt: endExclusive },
        toDate: { gte: start },
      },
      select: { employeeId: true, fromDate: true, toDate: true },
    }),
    db.holiday.findMany({
      where: { companyId, date: { gte: start, lt: endExclusive } },
      select: { date: true, name: true },
    }),
  ]);

  const holidayByDay = new Map<number, string>();
  for (const h of holidays) holidayByDay.set(h.date.getUTCDate(), h.name);

  const attByEmpDay = new Map<string, Map<number, Date | null>>();
  for (const a of attendance) {
    const day = a.date.getUTCDate();
    let m = attByEmpDay.get(a.employeeId);
    if (!m) { m = new Map(); attByEmpDay.set(a.employeeId, m); }
    m.set(day, a.checkIn);
  }
  const leavesByEmp = new Map<string, { from: Date; to: Date }[]>();
  for (const l of leaves) {
    let arr = leavesByEmp.get(l.employeeId);
    if (!arr) { arr = []; leavesByEmp.set(l.employeeId, arr); }
    arr.push({ from: l.fromDate, to: l.toDate });
  }

  const sundays: boolean[] = [];
  for (let d = 1; d <= daysInMonth; d++) {
    sundays.push(new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), d)).getUTCDay() === 0);
  }

  const rows: RegisterRow[] = employees.map((e) => {
    const attMap = attByEmpDay.get(e.id);
    const lv = leavesByEmp.get(e.id) ?? [];
    const cells: RegisterCell[] = [];
    let present = 0, absent = 0, leaveC = 0, off = 0;

    for (let d = 1; d <= daysInMonth; d++) {
      const dayDate = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), d);
      if (dayDate > todayUtcMid) { cells.push({ code: "" }); continue; }
      if (dayDate < e.joinDate.getTime()) { cells.push({ code: "" }); continue; }

      // attendance punch wins over everything else that day
      if (attMap?.has(d)) {
        const ci = attMap.get(d);
        present++;
        cells.push({ code: "P", inAt: ci ? minsToHHMM(istMins(ci)) : undefined });
        continue;
      }
      if (lv.some((l) => dayDate >= l.from.getTime() && dayDate <= l.to.getTime())) {
        leaveC++;
        cells.push({ code: "L" });
        continue;
      }
      const holName = holidayByDay.get(d);
      if (holName) { cells.push({ code: "H", note: holName }); continue; }
      const dow = new Date(dayDate).getUTCDay();
      if (dow === e.weeklyOff) { off++; cells.push({ code: "W" }); continue; }
      absent++;
      cells.push({ code: "A" });
    }

    return {
      employeeId: e.id,
      code: e.code,
      name: `${e.firstName} ${e.lastName}`,
      department: e.department?.name ?? null,
      cells,
      present,
      absent,
      leave: leaveC,
      weeklyOff: off,
    };
  });

  return { month, label, daysInMonth, sundays, rows };
}

// ---------------------------------------------------------------------------
// 2) Late-in report
// ---------------------------------------------------------------------------

export type LateRow = {
  employeeId: string;
  code: string;
  name: string;
  department: string | null;
  date: string;       // ISO yyyy-mm-dd
  dayLabel: string;   // "5 Sep"
  shiftStart: string; // "08:00"
  checkIn: string;    // "08:23"
  lateByMins: number;
};

function parseHM(s: string): number {
  const [h, m] = s.split(":").map(Number);
  return (h || 0) * 60 + (m || 0);
}

export async function buildLateIn(companyId: string, month: string) {
  const { start, endExclusive, label } = monthRange(month);

  const [employees, attendance] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true, shift: true },
    }),
    db.attendance.findMany({
      where: { companyId, date: { gte: start, lt: endExclusive }, checkIn: { not: null } },
      select: { employeeId: true, date: true, checkIn: true, note: true },
    }),
  ]);

  const baselineShift = await db.shift.findFirst({ where: { companyId }, orderBy: { startTime: "asc" } });
  const empById = new Map(employees.map((e) => [e.id, e]));

  const rows: LateRow[] = [];
  for (const a of attendance) {
    const e = empById.get(a.employeeId);
    if (!e || !a.checkIn) continue;
    const shift = e.shift ?? baselineShift;
    if (!shift) continue;
    const startMins = parseHM(shift.startTime);
    const inMins = istMins(a.checkIn);
    // treat punches up to 4h before start as the same-shift check-in (night-shift safe: skip)
    if (inMins < startMins - 240) continue;
    const lateBy = inMins - startMins;
    if (lateBy <= LATE_GRACE_MINS) continue;
    const dateIso = a.date.toISOString().slice(0, 10);
    const dayLabel = a.date.toLocaleDateString("en-IN", { day: "numeric", month: "short", timeZone: "UTC" });
    rows.push({
      employeeId: e.id,
      code: e.code,
      name: `${e.firstName} ${e.lastName}`,
      department: e.department?.name ?? null,
      date: dateIso,
      dayLabel,
      shiftStart: shift.startTime,
      checkIn: minsToHHMM(inMins),
      lateByMins: lateBy,
    });
  }

  rows.sort((a, b) => a.date.localeCompare(b.date) || a.name.localeCompare(b.name));
  return { label, rows };
}

// ---------------------------------------------------------------------------
// 3) OT report — worked-hours beyond shift duration + approved manual OT
// ---------------------------------------------------------------------------

export type OtRow = {
  employeeId: string;
  code: string;
  name: string;
  department: string | null;
  date: string;
  dayLabel: string;
  workedHours: number | null; // null = manual OT (no punch pair)
  shiftHours: number | null;
  otHours: number;
  source: "PUNCH" | "APPROVED_OT";
};

export async function buildOt(companyId: string, month: string) {
  const { start, endExclusive, label } = monthRange(month);

  const [employees, attendance, otReqs] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true, shift: true },
    }),
    db.attendance.findMany({
      where: { companyId, date: { gte: start, lt: endExclusive }, checkIn: { not: null }, checkOut: { not: null } },
      select: { employeeId: true, date: true, checkIn: true, checkOut: true },
    }),
    db.punchRequest.findMany({
      where: { companyId, type: "OT", status: "APPROVED", date: { gte: start, lt: endExclusive } },
      select: { employeeId: true, date: true, hours: true },
    }),
  ]);

  const baselineShift = await db.shift.findFirst({ where: { companyId }, orderBy: { startTime: "asc" } });
  const empById = new Map(employees.map((e) => [e.id, e]));

  const rows: OtRow[] = [];
  for (const a of attendance) {
    const e = empById.get(a.employeeId);
    if (!e || !a.checkIn || !a.checkOut) continue;
    const shift = e.shift ?? baselineShift;
    const shiftH = shift?.durationH ?? 9;
    const worked = (a.checkOut.getTime() - a.checkIn.getTime()) / 3600000;
    const ot = Math.floor((worked - shiftH) * 2) / 2; // half-hour buckets, only whole half-hours
    if (ot <= 0) continue;
    const dateIso = a.date.toISOString().slice(0, 10);
    rows.push({
      employeeId: e.id,
      code: e.code,
      name: `${e.firstName} ${e.lastName}`,
      department: e.department?.name ?? null,
      date: dateIso,
      dayLabel: a.date.toLocaleDateString("en-IN", { day: "numeric", month: "short", timeZone: "UTC" }),
      workedHours: Math.round(worked * 10) / 10,
      shiftHours: shiftH,
      otHours: ot,
      source: "PUNCH",
    });
  }
  for (const r of otReqs) {
    const e = empById.get(r.employeeId);
    if (!e || !r.hours) continue;
    const dateIso = r.date.toISOString().slice(0, 10);
    rows.push({
      employeeId: e.id,
      code: e.code,
      name: `${e.firstName} ${e.lastName}`,
      department: e.department?.name ?? null,
      date: dateIso,
      dayLabel: r.date.toLocaleDateString("en-IN", { day: "numeric", month: "short", timeZone: "UTC" }),
      workedHours: null,
      shiftHours: null,
      otHours: r.hours,
      source: "APPROVED_OT",
    });
  }

  rows.sort((a, b) => a.date.localeCompare(b.date) || a.name.localeCompare(b.name));
  const totalOt = rows.reduce((s, r) => s + r.otHours, 0);
  return { label, rows, totalOt: Math.round(totalOt * 10) / 10 };
}

// ---------------------------------------------------------------------------
// 4) Leave balance register (year-to-date, snapshot "as of today")
// ---------------------------------------------------------------------------

export type LeaveBalanceRow = {
  employeeId: string;
  code: string;
  name: string;
  department: string | null;
  category: string;
  /** per leave type id -> { name, quota, used, balance, pending } */
  balances: { leaveTypeId: string; name: string; quota: number; used: number; balance: number; pending: number }[];
};

export async function buildLeaveBalanceRegister(companyId: string) {
  const [employees, types] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true },
      orderBy: [{ firstName: "asc" }],
    }),
    db.leaveType.findMany({ where: { companyId }, orderBy: { daysPerYear: "desc" } }),
  ]);

  const rows: LeaveBalanceRow[] = [];
  for (const e of employees) {
    const bals = await getLeaveBalances(
      { id: e.id, category: e.category, joinDate: e.joinDate },
      companyId
    );
    rows.push({
      employeeId: e.id,
      code: e.code,
      name: `${e.firstName} ${e.lastName}`,
      department: e.department?.name ?? null,
      category: e.category,
      balances: bals.map((b) => ({
        leaveTypeId: b.leaveTypeId,
        name: b.name,
        quota: b.quota,
        used: b.used,
        balance: b.quota === 0 ? Infinity as unknown as number : Math.max(0, b.accrued - b.used),
        pending: b.pending,
      })),
    });
  }
  return { types, rows };
}

// ---------------------------------------------------------------------------
// 5) Gate pass log
// ---------------------------------------------------------------------------

export type GateLogRow = {
  id: string;
  code: string;
  name: string;
  department: string | null;
  date: string;
  dayLabel: string;
  exitAt: string;
  returnAt: string | null;
  reason: string | null;
  status: string;
  verified: boolean;
};

export async function buildGatePassLog(companyId: string, month: string) {
  const { start, endExclusive, label } = monthRange(month);

  const passes = await db.gatePass.findMany({
    where: { companyId, date: { gte: start, lt: endExclusive } },
    include: { employee: { include: { department: true } } },
    orderBy: [{ date: "asc" }, { exitAt: "asc" }],
  });

  const rows: GateLogRow[] = passes.map((g) => ({
    id: g.id,
    code: g.employee.code,
    name: `${g.employee.firstName} ${g.employee.lastName}`,
    department: g.employee.department?.name ?? null,
    date: g.date.toISOString().slice(0, 10),
    dayLabel: g.date.toLocaleDateString("en-IN", { day: "numeric", month: "short", timeZone: "UTC" }),
    exitAt: g.exitAt,
    returnAt: g.returnAt,
    reason: g.reason,
    status: g.status,
    verified: !!g.entryVerifiedAt,
  }));
  return { label, rows };
}
