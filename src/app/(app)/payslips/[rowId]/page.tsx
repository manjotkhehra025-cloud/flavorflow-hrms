import { Pa } from "@/components/Pa";

import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { btnGhost } from "@/components/ui";
import { monthName, monthNamePa } from "@/lib/utils";
import { getRequestLang } from "@/lib/i18n";
import { Icon } from "@/components/icons";
import { Payslip, type PayslipData } from "@/components/Payslip";
import { PrintButton } from "@/components/PrintButton";

export const dynamic = "force-dynamic";

function daysInMonth(month: string): number {
  const [y, m] = month.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** Employee's own payslip (own-only; staff should use the payroll run view instead). */
export default async function MyPayslipPage({ params }: { params: Promise<{ rowId: string }> }) {
  const me = await requireUser();
  const { rowId } = await params;
  const lang = await getRequestLang();

  const row = await db.payrollRow.findFirst({
    where: { id: rowId, run: { companyId: me.companyId, status: "LOCKED" } },
    include: { run: true, employee: { include: { department: true, company: true } } },
  });
  if (!row || row.employeeId !== me.employeeId) notFound();

  const e = row.employee;
  const monthly = e.salaryType !== "DAILY";
  const dim = daysInMonth(row.run.month);
  const fullBase = monthly ? row.baseAmount + row.deductions : row.baseAmount;

  const data: PayslipData = {
    month: row.run.month,
    monthLabel: lang === "pa" ? monthNamePa(row.run.month) : monthName(row.run.month),
    companyName: e.company.name,
    code: e.code,
    name: e.firstName + (e.lastName ? " " + e.lastName : ""),
    dept: e.department?.name ?? "—",
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
        <Link href="/payslips" className={btnGhost}><Icon name="chevron-down" className="h-3.5 w-3.5 rotate-90" /> <Pa>All payslips</Pa></Link>
        <PrintButton label={<Pa>🖨 Print / save PDF</Pa>} />
      </div>
      <Payslip d={data} />
    </div>
  );
}
