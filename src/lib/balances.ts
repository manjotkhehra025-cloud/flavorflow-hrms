import { db } from "./db";
import { toDateOnly } from "./utils";

export type LeaveBalance = {
  leaveTypeId: string;
  name: string;
  daysPerYear: number; // 0 = unlimited (unpaid)
  used: number;        // approved days this year
  pending: number;     // pending approval days
};

/** Used (APPROVED) + pending leave days per leave type for the current year. */
export async function getLeaveBalances(employeeId: string, companyId: string): Promise<LeaveBalance[]> {
  const year = new Date().getFullYear();
  const yearStart = toDateOnly(`${year}-01-01`);
  const yearEnd = toDateOnly(`${year}-12-31`);

  const [types, requests] = await Promise.all([
    db.leaveType.findMany({ where: { companyId }, orderBy: { name: "asc" } }),
    db.leaveRequest.findMany({
      where: {
        employeeId,
        status: { in: ["APPROVED", "PENDING"] },
        fromDate: { lte: yearEnd },
        toDate: { gte: yearStart },
      },
      select: { leaveTypeId: true, status: true, days: true },
    }),
  ]);

  return types.map((t) => ({
    leaveTypeId: t.id,
    name: t.name,
    daysPerYear: t.daysPerYear,
    used: requests.filter((r) => r.leaveTypeId === t.id && r.status === "APPROVED").reduce((s, r) => s + r.days, 0),
    pending: requests.filter((r) => r.leaveTypeId === t.id && r.status === "PENDING").reduce((s, r) => s + r.days, 0),
  }));
}
