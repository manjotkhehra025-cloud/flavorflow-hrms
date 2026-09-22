import { Pa } from "@/components/Pa";

import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { btnGhost } from "@/components/ui";
import { monthName } from "@/lib/utils";
import { Icon } from "@/components/icons";
import { Payslip, type PayslipData } from "@/components/Payslip";
import { PrintButton } from "@/components/PrintButton";

export const dynamic = "force-dynamic";

function daysInMonth(month: string): number {
  const [y, m] = month.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

export default async function PayslipPage({ params }: { params: Promise<{ id: string; rowId: string }> }) {
  const me = await requireStaff();
  const { id, rowId } = await params;

  const row = await db.payrollRow.findFirst({
    where: { id: rowId, runId: id },
    include: {
      run: true,
      employee: { include: { department: true, company: true } },
    },
  });
  if (!row || row.run.companyId !== me.companyId || row.run.status === "DRAFT") notFound();

  const e = row.employee;
  const monthly = e.salaryType !== "DAILY";
  const dim = daysInMonth(row.run.month);
  const fullBase = monthly ? row.baseAmount + row.deductions : row.baseAmount;
  const name = e.firstName + (e.lastName ? " " + e.lastName : "");

  const data: PayslipData = {
    month: row.run.month,
    monthLabel: monthName(row.run.month),
    companyName: e.company.name,
    code: e.code, name, dept: e.department?.name ?? "—",
    salaryType: e.salaryType,
    fullBase,
    baseHint: monthly ? `₹ ${fullBase.toLocaleString("en-IN")} / ${dim} days` : `${row.presentDays} days × ₹${e.dailyRate ?? 0}`,
    otHours: row.otHours, otRate: row.otRate, otAmount: row.otAmount,
    otherEarning: row.otherEarning, otherEarningNote: row.otherEarningNote,
    lopDays: row.lopDays, lopPerDay: monthly && dim > 0 ? Math.round((e.baseSalary ?? 0) / dim) : 0, lopAmount: row.deductions,
    pfEmployee: row.pfEmployee, pfEmployer: row.pfEmployer,
    esiEmployee: row.esiEmployee, esiEmployer: row.esiEmployer,
    advanceRecover: row.advanceRecover,
    otherDeduction: row.otherDeduction, otherDeductionNote: row.otherDeductionNote,
    netPay: row.netPay,
    paymentMode: row.paymentMode,
    bank: e.bankAccount ? "••" + e.bankAccount.slice(-4) : null,
    presentDays: row.presentDays, leaveDays: row.leaveDays, offDays: row.offDays, absentDays: row.absentDays,
  };

  return (
    <div className="mx-auto max-w-2xl space-y-4 print:space-y-0">
      <div className="flex items-center justify-between print:hidden">
        <Link href={`/payroll/${id}`} className={btnGhost}><Icon name="chevron-down" className="h-3.5 w-3.5 rotate-90" /> <Pa>Back to run</Pa></Link>
        <PrintButton label={<Pa>🖨 Print / save PDF</Pa>} />
      </div>
      <div className="print-area">
        <Payslip d={data} />
      </div>
    </div>
  );
}
