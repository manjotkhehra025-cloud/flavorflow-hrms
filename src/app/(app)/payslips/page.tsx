import { Pa } from "@/components/Pa";

import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { Card, PageHeader } from "@/components/ui";
import { fmtINR, monthName, monthNamePa } from "@/lib/utils";
import { getRequestLang } from "@/lib/i18n";
import { Icon } from "@/components/icons";

export const dynamic = "force-dynamic";

export default async function MyPayslipsPage() {
  const me = await requireUser();
  const lang = await getRequestLang();
  if (!me.employeeId) {
    return (
      <div className="space-y-4">
        <PageHeader title={<Pa>My payslips</Pa>} subtitle={<Pa>Your salary slips appear here after payroll is approved & locked.</Pa>} />
        <Card className="p-8 text-center text-sm text-slate-400">
          <Pa>Your login is not linked to an employee profile yet — ask HR.</Pa>
        </Card>
      </div>
    );
  }

  const rows = await db.payrollRow.findMany({
    where: { employeeId: me.employeeId, run: { companyId: me.companyId, status: "LOCKED" } },
    include: { run: true },
    orderBy: { run: { month: "desc" } },
  });

  const label = (m: string) => (lang === "pa" ? monthNamePa(m) : monthName(m));

  return (
    <div className="space-y-5">
      <PageHeader title={<Pa>My payslips</Pa>} subtitle={<Pa>Salary slips become visible here once payroll is locked.</Pa>} />

      {rows.length === 0 ? (
        <Card className="p-10 text-center">
          <div className="text-4xl"></div>
          <p className="mt-2 text-sm text-slate-500"><Pa>No payslips yet — they appear after your first locked payroll.</Pa></p>
        </Card>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {rows.map((r) => (
            <Link key={r.id} href={`/payslips/${r.id}`}
              className="group relative overflow-hidden rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:border-emerald-300 hover:shadow-md">
              <div className="absolute -right-6 -top-6 h-20 w-20 rounded-full bg-emerald-50 group-hover:bg-emerald-100 transition" />
              <div className="text-[10px] font-bold uppercase tracking-[0.14em] text-slate-400"><Pa>Salary slip</Pa> · {r.run.month}</div>
              <div className="mt-1 text-lg font-black text-slate-900">{label(r.run.month)}</div>
              <div className="mt-2 flex items-baseline gap-2">
                <span className="text-xl font-black text-emerald-700">{fmtINR(r.netPay)}</span>
                <span className="text-[11px] font-semibold text-slate-400"><Pa>net pay</Pa></span>
              </div>
              <div className="mt-2 inline-flex items-center gap-1 text-xs font-bold text-emerald-600">
                <Icon name="printer" className="h-3.5 w-3.5" /> <Pa>Open / print</Pa>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
