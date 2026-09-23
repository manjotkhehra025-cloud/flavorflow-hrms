import type { PayslipData } from "@/components/Payslip";
import { monthName, monthNamePa } from "@/lib/utils";
import type { PayrollRow, Employee, Department, PayrollRun, Company } from "@prisma/client";

type RowFull = PayrollRow & {
  employee: Employee & { department: Department | null; company: Company };
  run: PayrollRun;
};

function daysInMonth(month: string): number {
  const [y, m] = month.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

export function buildPayslipData(row: RowFull, lang: "en" | "pa"): PayslipData {
  const e = row.employee;
  const monthly = e.salaryType !== "DAILY";
  const dim = daysInMonth(row.run.month);
  const fullBase = monthly ? row.baseAmount + row.deductions : row.baseAmount;
  return {
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
    offWorkDays: row.offWorkDays, offWorkPay: row.offWorkPay,
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
}
