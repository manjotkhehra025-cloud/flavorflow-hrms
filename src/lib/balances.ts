import { Prisma } from "@prisma/client";
import { db } from "@/lib/db";

/**
 * Leave balance engine v2 (HRMate).
 *
 * Categories:
 *  - YELLOW_CARD: only Earned Leave (EL), hardcoded quota 15/yr, auto-accrued
 *    at 1.25 days per elapsed month of the calendar year (from join month).
 *  - OFFICIAL: all leave types with fixed yearly quotas (0 = unlimited/LOP).
 *
 * Adjustments (LeaveAdjustment.days): positive consumes balance, negative credits it.
 */

export type Balance = {
  leaveTypeId: string;
  name: string;
  quota: number;           // 0 = unlimited
  accrued: number;         // yellow-card: accrued so far this year; others = quota
  used: number;            // approved days this year
  adjusted: number;        // net adjustments (+ consumes, - credits)
  pending: number;
};

const YELLOW_QUOTA = 15;

function monthsAccruedFactor(joinDate: Date, now = new Date()): number {
  const y = now.getUTCFullYear();
  const m = now.getUTCMonth(); // 0-based
  let months = m + 1; // Jan → now, inclusive
  if (joinDate.getUTCFullYear() === y) {
    const jm = joinDate.getUTCMonth();
    months = Math.max(0, m - jm + 1);
  }
  return months;
}

export function elAccrued(joinDate: Date): number {
  const months = monthsAccruedFactor(joinDate);
  return Math.min(YELLOW_QUOTA, Math.round(months * 1.25 * 100) / 100);
}

export async function getLeaveBalances(
  employee: { id: string; category: string; joinDate: Date },
  companyId: string
): Promise<Balance[]> {
  const yearStart = new Date(Date.UTC(new Date().getUTCFullYear(), 0, 1));
  const yearEnd = new Date(Date.UTC(new Date().getUTCFullYear() + 1, 0, 1));

  const [types, reqs, adjustments] = await Promise.all([
    db.leaveType.findMany({ where: { companyId }, orderBy: { daysPerYear: "desc" } }),
    db.leaveRequest.findMany({
      where: {
        employeeId: employee.id,
        status: { in: ["PENDING", "APPROVED"] },
        fromDate: { gte: yearStart, lt: yearEnd },
      },
      select: { leaveTypeId: true, status: true, days: true },
    }),
    db.leaveAdjustment.findMany({
      where: { employeeId: employee.id, createdAt: { gte: yearStart, lt: yearEnd } },
      select: { leaveTypeId: true, days: true },
    }),
  ]);

  const used = new Map<string, number>();
  const pending = new Map<string, number>();
  for (const r of reqs) {
    const days = Prisma.Decimal.isDecimal(r.days) ? Number(r.days) : Number(r.days ?? 0);
    if (r.status === "APPROVED") used.set(r.leaveTypeId, (used.get(r.leaveTypeId) ?? 0) + days);
    else pending.set(r.leaveTypeId, (pending.get(r.leaveTypeId) ?? 0) + days);
  }
  const adj = new Map<string, number>();
  for (const a of adjustments) {
    adj.set(a.leaveTypeId, (Number(adj.get(a.leaveTypeId)) || 0) + Number(a.days));
  }

  if (employee.category === "YELLOW_CARD") {
    const el = types.find((t) => /earned/i.test(t.name));
    if (!el) return [];
    const accrued = elAccrued(employee.joinDate);
    return [
      {
        leaveTypeId: el.id,
        name: el.name,
        quota: YELLOW_QUOTA,
        accrued,
        used: used.get(el.id) ?? 0,
        adjusted: adj.get(el.id) ?? 0,
        pending: pending.get(el.id) ?? 0,
      },
    ];
  }

  return types.map((t) => ({
    leaveTypeId: t.id,
    name: t.name,
    quota: t.daysPerYear,
    accrued: t.daysPerYear,
    used: used.get(t.id) ?? 0,
    adjusted: adj.get(t.id) ?? 0,
    pending: pending.get(t.id) ?? 0,
  }));
}

/** Remaining usable days (clamped at 0); null means unlimited (LOP-type). */
export function balanceRemaining(b: Balance): number | null {
  if (b.quota === 0) return null;
  const raw = b.accrued - b.used - b.adjusted;
  return Math.max(0, Math.round(raw * 100) / 100);
}
