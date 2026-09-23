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
  daAmount: number;
  halfDays: number;
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
  pfEmployee: number;
  pfEmployer: number;
  esiEmployee: number;
  esiEmployer: number;
  offWorkDays: number;
  offWorkPay: number;
  advanceBalance: number;
  advanceRecover: number;
  otherDeduction: number;
  otherEarning: number;
  netPay: number;
  needsSetup: boolean;
};

export type Statutory = { pfEmployee: number; pfEmployer: number; esiEmployee: number; esiEmployer: number; pfWage: number; esiGross: number };

function quotaEnabled(v: number | null | undefined): boolean {
  return (v ?? 0) > 0;
}

/**
 * Indian statutory deductions:
 * - PF: 12% employee + 12% employer of PF-wage = min(earned basic, ₹15,000 cap). Only when employee.pfEnabled and basic > 0.
 * - ESI: 0.75% employee + 3.25% employer of gross (base ± extras, OT excluded by law). Only when employee.esiEnabled.
 *   Amounts are rounded UP to the next rupee (ESIC convention).
 */
export function computeStatutory(
  emp: { pfEnabled: boolean; esiEnabled: boolean },
  earnedBasic: number,
  otherEarning: number,
): Statutory {
  const pfWage = emp.pfEnabled && earnedBasic > 0 ? Math.min(earnedBasic, 15000) : 0;
  const pfEmployee = Math.round(pfWage * 0.12);
  const pfEmployer = Math.round(pfWage * 0.12);
  const esiGross = emp.esiEnabled ? Math.max(0, earnedBasic + otherEarning) : 0;
  const esiEmployee = esiGross > 0 ? Math.ceil(esiGross * 0.0075) : 0;
  const esiEmployer = esiGross > 0 ? Math.ceil(esiGross * 0.0325) : 0;
  return { pfEmployee, pfEmployer, esiEmployee, esiEmployer, pfWage, esiGross };
}

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

  const rules = await db.company.findUnique({ where: { id: companyId }, select: { dailyPaidLeaveDays: true, lateGraceMins: true, latesPerCut: true, daPercent: true, otMultiplier: true, shiftHours: true } });
  const [employees, attendance, leaves, holidays, advances, shifts] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true, shift: true },
      orderBy: [{ department: { name: "asc" } }, { code: "asc" }],
    }),
    db.attendance.findMany({ where: { companyId, date: { gte: start, lt: endPlus }, checkIn: { not: null } }, select: { employeeId: true, date: true, checkIn: true } }),
    db.leaveRequest.findMany({
      where: { companyId, status: "APPROVED", fromDate: { lt: endPlus }, toDate: { gte: start } },
      select: { employeeId: true, fromDate: true, toDate: true, halfDay: true },
    }),
    db.holiday.findMany({ where: { companyId, date: { gte: start, lt: endPlus } }, select: { date: true } }),
    db.advance.findMany({ where: { companyId }, select: { employeeId: true, amount: true, repaid: true, emi: true, givenDate: true }, orderBy: { givenDate: "asc" } }),
    db.shift.findMany({ where: { companyId } }),
  ]);
  const roster = await db.shiftAssignment.findMany({
    where: { companyId, date: { gte: start, lt: endPlus } },
    include: { shift: { select: { startTime: true } } },
  });
  const rosterMap = new Map<string, { isOff: boolean; startTime: string | null }>();
  for (const a of roster) {
    rosterMap.set(a.employeeId + "|" + dstr(a.date), { isOff: a.isOff, startTime: a.shift?.startTime ?? null });
  }
  const otReqs = await db.punchRequest.findMany({
    where: { companyId, type: "OT", status: "APPROVED", date: { gte: start, lt: endPlus }, hours: { not: null } },
    select: { employeeId: true, hours: true },
  });
  const otHoursMap = new Map<string, number>();
  for (const ot of otReqs) otHoursMap.set(ot.employeeId, (otHoursMap.get(ot.employeeId) ?? 0) + (ot.hours ?? 0));

  const yearStart = new Date(Date.UTC(y, 0, 1));
  const leavesEarlier = quotaEnabled(rules?.dailyPaidLeaveDays)
    ? await db.leaveRequest.findMany({
        where: { companyId, status: "APPROVED", fromDate: { lt: start }, toDate: { gte: yearStart } },
        select: { employeeId: true, fromDate: true, toDate: true, halfDay: true },
      })
    : [];
  const usedBeforeMap = new Map<string, number>();
  for (const lv of leavesEarlier) {
    let cur = new Date(Math.max(lv.fromDate.getTime(), yearStart.getTime()));
    const to = new Date(Math.min(lv.toDate.getTime(), start.getTime() - 1));
    for (; cur <= to; cur = new Date(cur.getTime() + DAY)) {
      usedBeforeMap.set(lv.employeeId, (usedBeforeMap.get(lv.employeeId) ?? 0) + 1);
    }
    if (lv.halfDay) usedBeforeMap.set(lv.employeeId, (usedBeforeMap.get(lv.employeeId) ?? 0) - 0.5);
  }

  // earliest check-in per employee+day (for the late-mark rule)
  const earliestIn = new Map<string, Date>();
  for (const a of attendance) {
    if (!a.checkIn) continue;
    const key = a.employeeId + "|" + dstr(a.date);
    const prev = earliestIn.get(key);
    if (!prev || a.checkIn < prev) earliestIn.set(key, a.checkIn);
  }

  // per-employee maps
  const rulesLatesPerCut = rules?.latesPerCut ?? 0;
  const rulesGrace = rules?.lateGraceMins ?? 15;
  const attMap = new Map<string, Set<string>>();
  const lateCount = new Map<string, number>();
  for (const a of attendance) {
    const k = dstr(a.date);
    if (!attMap.has(a.employeeId)) attMap.set(a.employeeId, new Set());
    attMap.get(a.employeeId)!.add(k);
    void a.checkIn; // late-check needs the shift start — computed per-employee below
  }
  const leaveMap = new Map<string, Set<string>>();
  const halfMap = new Map<string, Set<string>>();
  const totalLeaveDays = new Map<string, number>();
  for (const lv of leaves) {
    if (lv.halfDay) {
      const k = dstr(lv.fromDate);
      if (!halfMap.has(lv.employeeId)) halfMap.set(lv.employeeId, new Set());
      halfMap.get(lv.employeeId)!.add(k);
      totalLeaveDays.set(lv.employeeId, (totalLeaveDays.get(lv.employeeId) ?? 0) + 0.5);
      continue;
    }
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
  const advListMap = new Map<string, { amount: number; repaid: number; emi: number | null }[]>();
  for (const a of advances) {
    if (!advListMap.has(a.employeeId)) advListMap.set(a.employeeId, []);
    advListMap.get(a.employeeId)!.push(a);
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
    const halfLvs = halfMap.get(emp.id) ?? new Set<string>();

    let present = 0, leave = 0, absent = 0, off = 0, offWork = 0, half = 0;
    const joinD = dstr(emp.joinDate);
    for (let i = 0; i < dim; i++) {
      const day = new Date(start.getTime() + i * DAY);
      const k = dstr(day);
      if (k < joinD || k > dstr(new Date())) { continue; } // before joining or future: ignore
      const dow = day.getUTCDay();
      const rosterCell = rosterMap.get(emp.id + "|" + k);
      if (rosterCell?.isOff) { off++; continue; } // explicit roster off beats attendance
      const isOffDay = dow === emp.weeklyOff || holidaySet.has(k);
      if (att.has(k)) { if (isOffDay) { present++; offWork++; } else present++; continue; }
      if (lvs.has(k)) { leave++; continue; }
      if (halfLvs.has(k)) { half++; continue; } // approved half-day leave: 0.5 paid melt
      if (isOffDay) { off++; continue; }
      absent++;
    }

    const monthly = emp.salaryType !== "DAILY";

    // E4 late-mark rule (monthly staff): every N late-ins (past shift-start + grace) → 1 LOP day
    if (monthly && rulesLatesPerCut > 0) {
      const shiftStart = (emp.shift ?? defaultShift)?.startTime ?? "09:00";
      const [sh, sm] = shiftStart.split(":").map(Number);
      let lates = 0;
      for (const k of att) {
        const shiftStartDay = rosterMap.get(emp.id + "|" + k)?.startTime ?? shiftStart;
        const [dsh, dsm] = shiftStartDay.split(":").map(Number);
        const ci = earliestIn.get(emp.id + "|" + k);
        if (!ci) continue;
        const dayY = ci.getUTCFullYear(), dayM = ci.getUTCMonth(), dayD = ci.getUTCDate();
        const cutoff = new Date(Date.UTC(dayY, dayM, dayD, dsh, dsm + rulesGrace));
        if (ci >= cutoff) lates++;
      }
      const lateLop = Math.floor(lates / rulesLatesPerCut);
      if (lateLop > 0) {
        absent += lateLop;
        present = Math.max(0, present - lateLop);
      }
      lateCount.set(emp.id, lates);
    }

    const workedDays = present + leave + off + half * 0.5; // days eligible for pay before LOP
    const lopDays = absent + half * 0.5; // monthly: an approved half leave still costs 0.5 day; daily: handled via paid-leave quota
    let payableDays: number, baseAmount: number, lopAmount: number;

    if (monthly) {
      // monthly: salary covers the month; LOP cuts absences as a ₹ deduction (base/dim × lop)
      payableDays = Math.max(0, workedDays); // present + approved-leave + offs
      baseAmount = emp.baseSalary ?? 0;
      lopAmount = dim > 0 ? Math.round((baseAmount / dim) * lopDays) : 0;
    } else {
      // E3: daily-rate — present days + paid approved-leave (up to company annual quota)
      const quota = rules?.dailyPaidLeaveDays ?? 0;
      let paidLeave = 0;
      if (quota > 0 && (leave > 0 || half > 0)) {
        paidLeave = Math.min(leave + half * 0.5, Math.max(0, quota - (usedBeforeMap.get(emp.id) ?? 0)));
      }
      payableDays = present + paidLeave;
      baseAmount = (emp.dailyRate ?? 0) * payableDays;
      lopAmount = 0;
    }

    const gross = baseAmount - lopAmount;
    // Phase F1: yellow-card weekly-off/holiday duty pay — monthly: base/dim × off-worked days; daily: already in base (present pays)
    let offWorkPay = 0, offWorkDays = 0;
    if (emp.category === "YELLOW_CARD" && offWork > 0) {
      offWorkDays = offWork;
      if (monthly) offWorkPay = Math.round((dim > 0 ? (emp.baseSalary ?? 0) / dim : 0) * offWork);
    }
    // Phase G1: approved OT hours → ₹ (employee otRate wins; else auto rate × company multiplier)
    let otRate = autoOtRate(emp);
    const otHours = otHoursMap.get(emp.id) ?? 0;
    if (!(emp.otRate && emp.otRate > 0) && otRate > 0) otRate = Math.round(otRate * (rules?.otMultiplier ?? 1.5));
    const otAmount = Math.round(otHours * otRate);
    // Phase G2: dearnee allowance — % of earned basic (monthly staff)
    const daAmount = monthly && (rules?.daPercent ?? 0) > 0 ? Math.round(Math.max(0, gross) * (rules!.daPercent / 100)) : 0;
    // Phase G3: advance recovery — per-advance EMI if set, up to the 25%-of-gross cap overall
    const advs = advListMap.get(emp.id) ?? [];
    const cap = Math.round(Math.max(0, gross) * 0.25); // recovery cap: 25% of gross before extras
    let capLeft = cap, advanceRecover = 0, advBalance = 0;
    for (const a of advs) {
      const bal = a.amount - a.repaid;
      advBalance += bal;
      if (bal <= 0 || capLeft <= 0) continue;
      const take = Math.min(bal, a.emi ?? cap, capLeft);
      advanceRecover += take; capLeft -= take;
    }
    const stat = computeStatutory(emp, Math.max(0, gross) + daAmount, otAmount); // PF on basic+DA; ESI on wages incl. OT

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
      otHours,
      otRate,
      otAmount,
      deductions: lopAmount,
      daAmount,
      halfDays: half,
      offWorkDays,
      offWorkPay,
      pfEmployee: stat.pfEmployee,
      pfEmployer: stat.pfEmployer,
      esiEmployee: stat.esiEmployee,
      esiEmployer: stat.esiEmployer,
      advanceBalance: advBalance,
      advanceRecover,
      otherDeduction: 0,
      otherEarning: 0,
      netPay: Math.max(0, gross + offWorkPay + otAmount + daAmount - stat.pfEmployee - stat.esiEmployee - advanceRecover),
      needsSetup: false,
    });
  }

  return { month, dim, rows, setupPending };
}

function accountName(emp: { firstName: string; lastName: string | null }): string {
  return (emp.firstName + (emp.lastName ? " " + emp.lastName : "")).trim();
}
