import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { getPerms } from "@/lib/permissions";
import { monthName, monthNamePa } from "@/lib/utils";

export const dynamic = "force-dynamic";

/**
 * GET /api/payslips — my LOCKED payslips, newest month first (month chips on the
 * app). Gated by the super-admin canViewPayslip switch exactly like the web page.
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (!me.employeeId) return jsonError("Your login is not linked to an employee profile yet — ask HR.", 400);
  if (!(await getPerms(me.employeeId)).canViewPayslip) {
    return jsonError("Payslip viewing is turned off for you — ask the super admin.", 403);
  }
  const lang = req.nextUrl.searchParams.get("lang") === "pa" ? "pa" : "en";

  const rows = await db.payrollRow.findMany({
    where: { employeeId: me.employeeId, run: { companyId: me.companyId, status: "LOCKED" } },
    include: { run: { select: { month: true } } },
    orderBy: { run: { month: "desc" } },
    take: 24,
  });
  return NextResponse.json({
    payslips: rows.map((r) => ({
      id: r.id,
      month: r.run.month,
      label: lang === "pa" ? monthNamePa(r.run.month) : monthName(r.run.month),
      netPay: r.netPay,
    })),
  });
}
