// Phase D2: payroll calculation engine.
// Monthly model: (dim − LOP) × base/dim + OT(hrs × ₹/hr) − advance recovery − other deductions + other earnings.
// Daily model:  present-days × daily-rate + OT(hrs × ₹/hr) − ...same. Weekly-offs NOT paid for daily earners.

import { db } from "@/lib/db";
import type { Employee, Shift } from "@prisma/client";

const DAY = 24 * 60 * 60 * 1000;

function daysInMonth(month: string): number {
  const [y, m] = month.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

function dstr(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export type CalcRow = {
  employeeId: string;
  code: string;
  name: string;
  dept: string;
  salaryType: string;
  baseSalary: number | null;
  dailyRate: number | null;
  otRateLive: number | null;
  payableDays: number;
  presentDays: number;
  leaveDays: number;
  absentDays: number;
  offDays: number;
  lopDays: number;
  baseAmount: number;
  otHours: number;
  otRate: number;
  otAmount: number;
  deductions: number; // LOP ₹ (monthly)
  advanceBalance: number;
  advanceRecover: number;
  otherDeduction: number;
  otherEarning: number;
  netPay: number;
  needsSetup: boolean;
};

export type CalcResult = {
  month: string;
  dim: number;
  rows: CalcRow[];
  setupPending: number;
};

function autoOtRate(emp: Pick<Employee, "salaryType" | "baseSalary" | "dailyRate" | "otRate">): number {
  if (emp.otRate && emp.otRate > 0) return emp.otRate;
  if (emp.salaryType === "DAILY") return emp.dailyRate ? Math.round(emp.dailyRate / 9) : 0;
  return emp.baseSalary ? Math.round(emp.baseSalary / 26 / 9) : 0;
}

/** Duration of a shift in hours (fallback 9). */
function shiftH(shift: Shift | null | undefined): number {
  return shift?.durationH ?? 9;
}

/** Recompute a full payroll calculation for a company + month (YYYY-MM). */
export async function calculatePayroll(companyId: string, month: string): Promise<CalcResult> {
  const [y, m] = month.split("-").map(Number);
  const start = new Date(Date.UTC(y, m - 1, 1));
  const dim = daysInMonth(month);
  const endPlus = new Date(Date.UTC(y, m - 1, dim + 1)); // exclusive

  const [employees, attendance, leaves, holidays, advances, shifts] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true, shift: true },
      orderBy: [{ department: { name: "asc" } }, { code: "asc" }],
    }),
    db.attendance.findMany({ where: { companyId, date: { gte: start, lt: endPlus }, checkIn: { not: null } }, select: { employeeId: true, date: true } }),
    db.leaveRequest.findMany({
      where: { companyId, status: "APPROVED", fromDate: { lt: endPlus }, toDate: { gte: start } },
      select: { employeeId: true, fromDate: true, toDate: true },
    }),
    db.holiday.findMany({ where: { companyId, date: { gte: start, lt: endPlus } }, select: { date: true } }),
    db.advance.findMany({ where: { companyId }, select: { employeeId: true, amount: true, repaid: true } }),
    db.shift.findMany({ where: { companyId } }),
  ]);

  // per-employee maps
  const attMap = new Map<string, Set<string>>();
  for (const a of attendance) {
    const k = dstr(a.date);
    if (!attMap.has(a.employeeId)) attMap.set(a.employeeId, new Set());
    attMap.get(a.employeeId)!.add(k);
  }
  const leaveMap = new Map<string, Set<string>>();
  const totalLeaveDays = new Map<string, number>();
  for (const lv of leaves) {
    let cur = new Date(Math.max(lv.fromDate.getTime(), start.getTime()));
    const to = new Date(Math.min(lv.toDate.getTime(), endPlus.getTime() - 1));
    let n = 0;
    for (; cur <= to; cur = new Date(cur.getTime() + DAY)) {
      const k = dstr(cur);
      if (!leaveMap.has(lv.employeeId)) leaveMap.set(lv.employeeId, new Set());
      leaveMap.get(lv.employeeId)!.add(k);
      n++;
    }
    totalLeaveDays.set(lv.employeeId, (totalLeaveDays.get(lv.employeeId) ?? 0) + n);
  }
  const holidaySet = new Set(holidays.map((h) => dstr(h.date)));
  const advMap = new Map<string, number>();
  for (const a of advances) {
    advMap.set(a.employeeId, (advMap.get(a.employeeId) ?? 0) + (a.amount - a.repaid));
  }
  const defaultShift = shifts[0] ?? null;

  const rows: CalcRow[] = [];
  let setupPending = 0;

  for (const emp of employees) {
    const hasSalary = emp.salaryType === "DAILY" ? (emp.dailyRate ?? 0) > 0 : (emp.baseSalary ?? 0) > 0;
    if (!hasSalary) { setupPending++; continue; } // listed on run page as "setup pending"

    const shift = emp.shift ?? defaultShift;
    void shiftH(shift); // (shift length reserved for upcoming half-day logic)
    const att = attMap.get(emp.id) ?? new Set<string>();
    const lvs = leaveMap.get(emp.id) ?? new Set<string>();

    let present = 0, leave = 0, absent = 0, off = 0;
    const joinD = dstr(emp.joinDate);
    for (let i = 0; i < dim; i++) {
      const day = new Date(start.getTime() + i * DAY);
      const k = dstr(day);
      if (k < joinD || k > dstr(new Date())) { continue; } // before joining or future: ignore
      const dow = day.getUTCDay();
      if (att.has(k)) { present++; continue; }
      if (lvs.has(k)) { leave++; continue; }
      if (dow === emp.weeklyOff || holidaySet.has(k)) { off++; continue; }
      absent++;
    }

    const monthly = emp.salaryType !== "DAILY";
    const workedDays = present + leave + off; // days eligible for pay before LOP
    const lopDays = absent;
    let payableDays: number, baseAmount: number, lopAmount: number;

    if (monthly) {
      // monthly: salary covers the month; LOP cuts absences as a ₹ deduction (base/dim × lop)
      payableDays = Math.max(0, workedDays); // present + approved-leave + offs
      baseAmount = emp.baseSalary ?? 0;
      lopAmount = dim > 0 ? Math.round((baseAmount / dim) * lopDays) : 0;
    } else {
      // daily-rate pays only days on duty (present + approved leave-with-pay? No — present only)
      payableDays = present;
      baseAmount = (emp.dailyRate ?? 0) * present;
      lopAmount = 0;
    }

    const gross = baseAmount - lopAmount;
    const advBalance = advMap.get(emp.id) ?? 0;
    const cap = Math.round(Math.max(0, gross) * 0.25); // recovery cap: 25% of gross before extras
    const advanceRecover = Math.min(cap, advBalance);
    const otRate = autoOtRate(emp);

    rows.push({
      employeeId: emp.id,
      code: emp.code,
      name: accountName(emp),
      dept: emp.department?.name ?? "—",
      salaryType: emp.salaryType,
      baseSalary: emp.baseSalary,
      dailyRate: emp.dailyRate,
      otRateLive: otRate,
      payableDays,
      presentDays: present,
      leaveDays: leave,
      absentDays: absent,
      offDays: off,
      lopDays,
      baseAmount: Math.max(0, gross),
      otHours: 0,
      otRate,
      otAmount: 0,
      deductions: lopAmount,
      advanceBalance: advBalance,
      advanceRecover,
      otherDeduction: 0,
      otherEarning: 0,
      netPay: Math.max(0, gross - advanceRecover),
      needsSetup: false,
    });
  }

  return { month, dim, rows, setupPending };
}

function accountName(emp: { firstName: string; lastName: string | null }): string {
  return (emp.firstName + (emp.lastName ? " " + emp.lastName : "")).trim();
}
