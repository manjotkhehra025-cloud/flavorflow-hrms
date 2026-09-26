import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { getLeaveBalances, balanceRemaining } from "@/lib/balances";
import { todayDate } from "@/lib/utils";

export const dynamic = "force-dynamic";

/**
 * GET /api/employees/:id — full profile for staff (parity row 13).
 * Mirrors web /employees/[id] data: basics, dept, desig, shift, login,
 * attendance (last 31d), leaves (10), balances, KYC, letters, pay, perms.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role === "EMPLOYEE") return jsonError("Only HR / admin can view employee profiles.", 403);

  const { id } = await params;

  const employee = await db.employee.findFirst({
    where: { id, companyId: me.companyId },
    include: {
      department: true,
      designation: true,
      shift: true,
      manager: { select: { id: true, firstName: true, lastName: true, code: true } },
      users: { select: { id: true, email: true, role: true, isActive: true } },
      permission: true,
      advances: { orderBy: { givenDate: "desc" }, take: 10 },
      salaryRevisions: { orderBy: { createdAt: "desc" }, take: 12 },
      kycDocs: { orderBy: { createdAt: "desc" } },
      letters: { orderBy: { createdAt: "desc" }, take: 20 },
    },
  });

  if (!employee) return jsonError("Employee not found.", 404);

  const monthStart = new Date(Date.UTC(todayDate().getUTCFullYear(), todayDate().getUTCMonth(), 1));

  const [attendance, leaves, balances, payrollRows] = await Promise.all([
    db.attendance.findMany({
      where: { employeeId: employee.id, date: { gte: monthStart } },
      orderBy: { date: "desc" },
      take: 31,
    }),
    db.leaveRequest.findMany({
      where: { employeeId: employee.id },
      include: { leaveType: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
      take: 12,
    }),
    getLeaveBalances(employee, me.companyId).catch(() => [] as any),
    db.payrollRow.findMany({
      where: { employeeId: employee.id },
      include: { run: { select: { month: true, status: true } } },
      orderBy: { run: { month: "desc" } },
      take: 6,
    }),
  ]);

  const balancesOut = (balances as any[]).map((b: any) => ({
    type: b.leaveType?.name ?? b.name ?? "Leave",
    quota: b.quota ?? b.daysPerYear ?? 0,
    used: b.used ?? 0,
    remaining: balanceRemaining ? (() => { try { return balanceRemaining(b); } catch { return 0; } })() : (b.remaining ?? 0),
  }));

  return NextResponse.json({
    employee: {
      id: employee.id,
      code: employee.code,
      name: `${employee.firstName} ${employee.lastName}`.trim(),
      firstName: employee.firstName,
      lastName: employee.lastName,
      email: employee.email ?? null,
      phone: employee.phone ?? null,
      gender: employee.gender ?? null,
      bloodGroup: employee.bloodGroup ?? null,
      emergencyName: employee.emergencyName ?? null,
      emergencyPhone: employee.emergencyPhone ?? null,
      dateOfBirth: employee.dateOfBirth ? employee.dateOfBirth.toISOString().slice(0, 10) : null,
      joinDate: employee.joinDate.toISOString().slice(0, 10),
      address: employee.address ?? null,
      status: employee.status,
      category: employee.category,
      contractor: employee.contractor ?? null,
      weeklyOff: employee.weeklyOff,
      photo: employee.photoExt ? `/api/photo/${employee.id}` : null,
      department: employee.department ? { id: employee.department.id, name: employee.department.name } : null,
      designation: employee.designation ? { id: employee.designation.id, title: employee.designation.title } : null,
      shift: employee.shift ? { id: employee.shift.id, name: employee.shift.name, startTime: employee.shift.startTime, durationH: employee.shift.durationH } : null,
      manager: employee.manager ? { id: employee.manager.id, name: `${employee.manager.firstName} ${employee.manager.lastName}`.trim(), code: employee.manager.code } : null,
      salaryType: employee.salaryType,
      baseSalary: employee.baseSalary ?? null,
      dailyRate: employee.dailyRate ?? null,
      otRate: employee.otRate ?? null,
      bankAccount: employee.bankAccount ?? null,
      ifsc: employee.ifsc ?? null,
      pfEnabled: employee.pfEnabled,
      pfNumber: employee.pfNumber ?? null,
      esiEnabled: employee.esiEnabled,
      esiNumber: employee.esiNumber ?? null,
    },
    login: employee.users[0] ? { id: employee.users[0].id, email: employee.users[0].email, role: employee.users[0].role, isActive: employee.users[0].isActive } : null,
    permissions: employee.permission
      ? {
          canPunch: employee.permission.canPunch,
          canApplyLeave: employee.permission.canApplyLeave,
          canGatePass: employee.permission.canGatePass,
          canSwapShift: employee.permission.canSwapShift,
          canSocialPost: employee.permission.canSocialPost,
          canViewPayslip: employee.permission.canViewPayslip,
        }
      : null,
    attendance: attendance.map((a: any) => ({
      date: a.date.toISOString().slice(0, 10),
      status: a.status,
      checkIn: a.checkIn ? a.checkIn.toISOString() : null,
      checkOut: a.checkOut ? a.checkOut.toISOString() : null,
      note: a.note ?? null,
    })),
    leaves: leaves.map((l: any) => ({
      id: l.id,
      type: (l as any).leaveType?.name ?? "Leave",
      fromDate: l.fromDate.toISOString().slice(0, 10),
      toDate: l.toDate.toISOString().slice(0, 10),
      days: l.days,
      status: l.status,
      reason: l.reason ?? null,
    })),
    balances: balancesOut,
    advances: employee.advances.map((a: any) => ({
      id: a.id,
      amount: a.amount,
      repaid: a.repaid,
      emi: a.emi ?? null,
      givenDate: a.givenDate.toISOString().slice(0, 10),
      reason: a.reason ?? null,
    })),
    salaryRevisions: employee.salaryRevisions.map((r: any) => ({
      id: r.id,
      effectiveDate: r.effectiveDate.toISOString().slice(0, 10),
      changeType: r.changeType,
      oldSalaryType: r.oldSalaryType ?? null,
      newSalaryType: r.newSalaryType ?? null,
      oldSalary: r.oldSalary ?? null,
      newSalary: r.newSalary ?? null,
      note: r.note ?? null,
    })),
    kycDocs: employee.kycDocs.map((d: any) => ({
      id: d.id,
      docType: d.docType,
      refNumber: d.refNumber,
      createdAt: d.createdAt.toISOString().slice(0, 10),
    })),
    letters: employee.letters.map((l: any) => ({
      id: l.id,
      serial: l.serial,
      type: l.type,
      issuedTo: l.issuedTo ?? null,
      createdAt: l.createdAt.toISOString().slice(0, 10),
    })),
    payroll: payrollRows.map((pr: any) => ({
      id: pr.id,
      runId: pr.runId,
      month: pr.run.month,
      status: pr.run.status,
      payableDays: pr.payableDays,
      presentDays: pr.presentDays,
      netPay: pr.netPay,
    })),
  });
}
