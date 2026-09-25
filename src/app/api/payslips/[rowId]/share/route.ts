import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { getPerms } from "@/lib/permissions";

/**
 * POST /api/payslips/:rowId/share — mint (or reuse) the public token link for my
 * own LOCKED slip. The link opens the printable page (Print → Save as PDF),
 * same token the web "Share link" button produces.
 */
export async function POST(req: NextRequest, { params }: { params: Promise<{ rowId: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (!me.employeeId) return jsonError("Your login is not linked to an employee profile yet — ask HR.", 400);
  if (!(await getPerms(me.employeeId)).canViewPayslip) {
    return jsonError("Payslip viewing is turned off for you — ask the super admin.", 403);
  }
  const { rowId } = await params;
  const row = await db.payrollRow.findFirst({
    where: { id: rowId, employeeId: me.employeeId, run: { companyId: me.companyId, status: "LOCKED" } },
    select: { id: true },
  });
  if (!row) return jsonError("Payslip not found (or payroll not locked yet).", 404);
  const link = await db.payslipLink.upsert({
    where: { rowId: row.id },
    update: {},
    create: { rowId: row.id, companyId: me.companyId },
  });
  const path = `/share/payslip/${link.token}`;
  return NextResponse.json({ path, url: new URL(path, req.nextUrl.origin).toString() });
}
