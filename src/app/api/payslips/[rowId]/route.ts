import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { getPerms } from "@/lib/permissions";
import { buildPayslipData } from "@/lib/payslipData";

export const dynamic = "force-dynamic";

type Line = { label: string; hint?: string; amount: number };

/**
 * GET /api/payslips/:rowId — one slip (own only), pre-split into earning /
 * deduction lines so the phone renders exactly what the printed slip shows.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ rowId: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (!me.employeeId) return jsonError("Your login is not linked to an employee profile yet — ask HR.", 400);
  if (!(await getPerms(me.employeeId)).canViewPayslip) {
    return jsonError("Payslip viewing is turned off for you — ask the super admin.", 403);
  }
  const { rowId } = await params;
  const lang = req.nextUrl.searchParams.get("lang") === "pa" ? "pa" : "en";

  const row = await db.payrollRow.findFirst({
    where: { id: rowId, employeeId: me.employeeId, run: { companyId: me.companyId, status: "LOCKED" } },
    include: { run: true, employee: { include: { department: true, company: true } } },
  });
  if (!row) return jsonError("Payslip not found.", 404);

  const d = buildPayslipData(row, lang);
  const earnings: Line[] = [{ label: "Base pay", hint: d.baseHint, amount: d.fullBase }];
  if (d.daAmount > 0) earnings.push({ label: "Dearness allowance", amount: d.daAmount });
  if (d.otAmount > 0) earnings.push({ label: "Overtime", hint: `${d.otHours}h × ₹${d.otRate}`, amount: d.otAmount });
  if (d.offWorkPay > 0) earnings.push({ label: "Weekly-off duty pay", hint: `${d.offWorkDays} off-day(s) worked`, amount: d.offWorkPay });
  if (d.otherEarning > 0) earnings.push({ label: "Reward / bonus", hint: d.otherEarningNote ?? undefined, amount: d.otherEarning });

  const deductions: Line[] = [];
  if (d.lopAmount > 0) deductions.push({ label: "Absent (LOP)", hint: `${d.lopDays} days × ₹${d.lopPerDay}`, amount: d.lopAmount });
  if (d.pfEmployee > 0) deductions.push({ label: "Provident Fund (12%)", amount: d.pfEmployee });
  if (d.esiEmployee > 0) deductions.push({ label: "ESI (0.75%)", amount: d.esiEmployee });
  if (d.advanceRecover > 0) deductions.push({ label: "Advance recovery", amount: d.advanceRecover });
  if (d.otherDeduction > 0) deductions.push({ label: "Other deduction", hint: d.otherDeductionNote ?? undefined, amount: d.otherDeduction });

  const sum = (ls: Line[]) => ls.reduce((a, l) => a + l.amount, 0);
  return NextResponse.json({
    payslip: {
      id: row.id,
      month: d.month,
      monthLabel: d.monthLabel,
      companyName: d.companyName,
      name: d.name,
      code: d.code,
      dept: d.dept,
      salaryType: d.salaryType,
      earnings,
      deductions,
      totalEarnings: sum(earnings),
      totalDeductions: sum(deductions),
      netPay: d.netPay,
      paymentMode: d.paymentMode,
      bank: d.bank,
      days: { present: d.presentDays, leave: d.leaveDays, off: d.offDays, absent: d.absentDays, payable: row.payableDays },
      employerPf: d.pfEmployer,
      employerEsi: d.esiEmployer,
    },
  });
}
