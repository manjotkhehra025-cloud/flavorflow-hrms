import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";

/** Staff: NEFT/IMPS bank-upload file (CSV) for a LOCKED payroll run. */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const me = await requireStaff();
  const { id } = await params;
  const run = await db.payrollRun.findFirst({
    where: { id, companyId: me.companyId, status: "LOCKED" },
    include: { rows: { include: { employee: { select: { code: true, firstName: true, lastName: true, bankAccount: true, ifsc: true } } } } },
  });
  if (!run) return NextResponse.json({ error: "Locked payroll run not found." }, { status: 404 });

  const esc = (v: string) => `"${v.replace(/"/g, '""')}"`;
  const lines: string[] = ["Sr No,Employee Code,Beneficiary Name,Account Number,IFSC,Amount (INR),Mode,Narration"];
  let sr = 0;
  for (const r of run.rows) {
    if (r.netPay <= 0) continue;
    const acct = r.employee.bankAccount?.replace(/\s/g, "") ?? "";
    const ifsc = r.employee.ifsc?.toUpperCase() ?? "";
    const name = (r.employee.firstName + (r.employee.lastName ? " " + r.employee.lastName : "")).trim();
    lines.push([String(++sr), r.employee.code, esc(name), `"${acct}"`, ifsc, String(r.netPay), acct ? "NEFT" : "CASH", esc(`SALARY ${run.month}`)].join(","));
  }

  return new NextResponse(lines.join("\r\n"), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="neft-${run.month}.csv"`,
    },
  });
}
