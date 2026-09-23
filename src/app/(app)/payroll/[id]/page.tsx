import { Pa } from "@/components/Pa";

import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Card, PageHeader, Badge, btnGhost } from "@/components/ui";
import { monthName, fmtINR } from "@/lib/utils";
import { Icon } from "@/components/icons";
import { RunEditor } from "./RunEditor";
import { RunView } from "./RunView";

export const dynamic = "force-dynamic";

export default async function PayrollRunPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireStaff();
  const { id } = await params;

  const run = await db.payrollRun.findFirst({
    where: { id, companyId: me.companyId },
    include: {
      rows: {
        include: {
          employee: {
            select: {
              id: true, code: true, firstName: true, lastName: true, salaryType: true,
              baseSalary: true, dailyRate: true, otRate: true, bankAccount: true, ifsc: true,
              pfEnabled: true, esiEnabled: true, category: true,
              department: { select: { name: true } },
              advances: true,
            },
          },
        },
        orderBy: { id: "asc" },
      },
    },
  });
  if (!run) notFound();
  const locker = run.approvedById
    ? await db.user.findUnique({ where: { id: run.approvedById }, select: { name: true } })
    : null;

  const total = run.rows.reduce((s, r) => s + r.netPay, 0);
  const payload = run.rows.map((r) => ({
    id: r.id,
    code: r.employee.code,
    name: r.employee.firstName + (r.employee.lastName ? " " + r.employee.lastName : ""),
    dept: r.employee.department?.name ?? "—",
    salaryType: r.employee.salaryType,
    baseSalary: r.employee.baseSalary,
    dailyRate: r.employee.dailyRate,
    payableDays: r.payableDays, presentDays: r.presentDays, leaveDays: r.leaveDays,
    absentDays: r.absentDays, offDays: r.offDays, lopDays: r.lopDays,
    baseAmount: r.baseAmount, deductions: r.deductions,
    otHours: r.otHours, otRate: r.otRate, otAmount: r.otAmount,
    daAmount: r.daAmount, halfDays: r.halfDays,
    advanceBalance: r.employee.advances.reduce((s, a) => s + (a.amount - a.repaid), 0),
    pfEnabled: r.employee.pfEnabled, esiEnabled: r.employee.esiEnabled,
    offWorkDays: r.offWorkDays, offWorkPay: r.offWorkPay, category: r.employee.category,
    pfEmployee: r.pfEmployee, pfEmployer: r.pfEmployer, esiEmployee: r.esiEmployee, esiEmployer: r.esiEmployer,
    advanceRecover: r.advanceRecover,
    otherDeduction: r.otherDeduction, otherDeductionNote: r.otherDeductionNote,
    otherEarning: r.otherEarning, otherEarningNote: r.otherEarningNote,
    paymentMode: r.paymentMode,
    bank: r.employee.bankAccount ? "••" + r.employee.bankAccount.slice(-4) : null,
    netPay: r.netPay,
    employeeId: r.employee.id,
  }));

  return (
    <div className="space-y-5">
      <PageHeader
        title={<>{monthName(run.month)} — <Pa>Payroll</Pa></>}
        subtitle={run.status === "DRAFT"
          ? <Pa>DRAFT — tweak OT / advances / deductions, then Approve & lock.</Pa>
          : <Pa>Locked — payslips live for employees. Download Excel pack below.</Pa>}
        actions={(
          <>
            {run.status === "DRAFT" ? <Badge tone="slate"><Pa>DRAFT</Pa></Badge> : <Badge tone="green">🔒 <Pa>LOCKED</Pa></Badge>}
            <Link href="/payroll" className={btnGhost}><Icon name="chevron-down" className="h-3.5 w-3.5 rotate-90" /> <Pa>All runs</Pa></Link>
          </>
        )}
      />

      <Card className="flex flex-wrap items-center gap-4 px-5 py-4">
        <Stat k={<Pa>Employees</Pa>} v={String(run.rows.length)} />
        <Stat k={<Pa>Net payout</Pa>} v={fmtINR(total)} strong />
        <Stat k={<Pa>OT payout</Pa>} v={fmtINR(run.rows.reduce((s, r) => s + r.otAmount, 0))} />
        <Stat k={<Pa>Advance recovered</Pa>} v={fmtINR(run.rows.reduce((s, r) => s + r.advanceRecover, 0))} />
        <Stat k={<Pa>Employer PF + ESI (company)</Pa>} v={fmtINR(run.rows.reduce((s, r) => s + r.pfEmployer + r.esiEmployer, 0))} />
        {locker && <Stat k={<Pa>Locked by</Pa>} v={locker.name} />}
      </Card>

      {run.status === "DRAFT" ? (
        <RunEditor runId={run.id} month={run.month} rows={payload} />
      ) : (
        <RunView runId={run.id} month={run.month} rows={payload} />
      )}
    </div>
  );
}

function Stat({ k, v, strong = false }: { k: React.ReactNode; v: string; strong?: boolean }) {
  return (
    <div>
      <div className="text-[9.5px] font-bold uppercase tracking-[0.14em] text-slate-500">{k}</div>
      <div className={"text-lg " + (strong ? "font-black text-emerald-700" : "font-bold text-slate-900")}>{v}</div>
    </div>
  );
}
