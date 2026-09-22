import { Pa } from "@/components/Pa";

import Link from "next/link";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Card, PageHeader, Badge, btnGhost, btnBrand } from "@/components/ui";
import { monthName, fmtINR } from "@/lib/utils";
import { Icon } from "@/components/icons";
import { computePayrollAction } from "@/actions/payroll";
import { PayrollDashboard } from "@/components/PayrollDashboard";

export const dynamic = "force-dynamic";

function statusBadge(status: string) {
  if (status === "LOCKED") return <Badge tone="green">🔒 <Pa>LOCKED</Pa></Badge>;
  if (status === "APPROVED") return <Badge tone="amber"><Pa>APPROVED</Pa></Badge>;
  return <Badge tone="slate">🧾 <Pa>DRAFT</Pa></Badge>;
}

export default async function PayrollPage({ searchParams }: { searchParams: Promise<{ err?: string }> }) {
  const me = await requireStaff();
  const { err } = await searchParams;

  const now = new Date();
  const defaultMonth = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
  const runs = await db.payrollRun.findMany({
    where: { companyId: me.companyId },
    include: { rows: { select: { netPay: true, pfEmployer: true, esiEmployer: true } }, _count: { select: { rows: true } } },
    orderBy: { month: "desc" },
  });
  // dashboard data: last 6 runs trend + latest-run dept / contractor split
  const trend = runs.slice(0, 6).map((r) => ({
    month: r.month, status: r.status,
    net: r.rows.reduce((a, x) => a + x.netPay, 0),
    employer: r.rows.reduce((a, x) => a + x.pfEmployer + x.esiEmployer, 0),
    staff: r._count.rows,
  }));
  const latestFull = runs[0]
    ? await db.payrollRow.findMany({ where: { runId: runs[0].id }, include: { employee: { include: { department: true } } } })
    : [];
  const deptMap = new Map<string, { label: string; net: number; staff: number }>();
  const conMap = new Map<string, { label: string; net: number; staff: number }>();
  for (const row of latestFull) {
    const label = row.employee.department?.name ?? "—";
    const cur = deptMap.get(label) ?? { label, net: 0, staff: 0 };
    cur.net += row.netPay; cur.staff++;
    deptMap.set(label, cur);
    if (row.employee.contractor) {
      const cl = row.employee.contractor;
      const cc = conMap.get(cl) ?? { label: cl, net: 0, staff: 0 };
      cc.net += row.netPay; cc.staff++;
      conMap.set(cl, cc);
    }
  }
  const deptSplit = [...deptMap.values()].sort((a, b) => b.net - a.net);
  const contractorSplit = [...conMap.values()].sort((a, b) => b.net - a.net);
  const shirtsCount = await db.employee.count({ where: { companyId: me.companyId, status: "ACTIVE", salaryType: "MONTHLY" } });
  const dailyCount = await db.employee.count({ where: { companyId: me.companyId, status: "ACTIVE", salaryType: "DAILY" } });

  return (
    <div className="space-y-6">
      <PageHeader
        title={<Pa>Payroll 🧾</Pa>}
        subtitle={<Pa>Monthly salary & daily-rate payouts — attendance picked up automatically.</Pa>}
      />

      <PayrollDashboard
        runs={trend}
        deptSplit={deptSplit}
        contractorSplit={contractorSplit}
        latestMonth={runs[0]?.month ?? null}
      />

      {err && (
        <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-semibold text-amber-800 overlay-dismiss">{err}</div>
      )}

      {/* compute form */}
      <Card className="p-6">
        <div className="mb-1 text-sm font-bold text-slate-900"><Pa>Run payroll</Pa></div>
        <p className="mb-4 text-xs text-slate-500">
          <Pa>Picks present / leave / LOP days from attendance, applies auto OT-rate & advance recovery (25% cap), builds a DRAFT you can tweak.</Pa>
        </p>
        <form action={async (fd: FormData) => { "use server"; await computePayrollAction({}, fd); }} className="flex flex-wrap items-end gap-3">
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Pa>Month</Pa></span>
            <input type="month" name="month" defaultValue={defaultMonth} required className="input" />
          </label>
          <button type="submit" className={btnBrand}>⚙️ <Pa>Compute payroll</Pa></button>
          {(shirtsCount + dailyCount) === 0 && (
            <span className="text-xs text-amber-600"><Pa>No salary set for anyone yet — set it on each employee profile first.</Pa></span>
          )}
        </form>
        <p className="mt-3 text-[11px] text-slate-400">
          <Pa>Employees with salary set</Pa>: {shirtsCount + dailyCount} (<Pa>monthly</Pa> {shirtsCount} · <Pa>daily-rate</Pa> {dailyCount})
        </p>
      </Card>

      {/* runs list */}
      <Card className="overflow-hidden">
        <div className="border-b border-slate-100 px-6 py-4 text-sm font-bold text-slate-900"><Pa>Payroll history</Pa></div>
        {runs.length === 0 ? (
          <div className="px-6 py-10 text-center text-sm text-slate-400"><Pa>No payroll runs yet — compute your first month above.</Pa></div>
        ) : (
          <ul className="divide-y divide-slate-100">
            {runs.map((run) => {
              const total = run.rows.reduce((s, r) => s + r.netPay, 0);
              return (
                <li key={run.id} className="flex items-center gap-3 px-4 sm:px-6 py-3.5">
                  <div className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-emerald-500 to-emerald-700 text-white font-black text-[11px] leading-none">
                    {run.month.slice(5, 7)}<br className="hidden" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-bold text-slate-900">{monthName(run.month)}</span>
                      {statusBadge(run.status)}
                    </div>
                    <div className="mt-0.5 text-xs text-slate-500">
                      {run._count.rows} <Pa>employees</Pa> · <b className="text-slate-700">{fmtINR(total)}</b> <Pa>net payout</Pa>
                    </div>
                  </div>
                  <Link href={`/payroll/${run.id}`} className={btnGhost}>
                    {run.status === "DRAFT" ? <Pa>Edit draft</Pa> : <Pa>Open</Pa>} <Icon name="chevron-down" className="h-3.5 w-3.5 -rotate-90" />
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </Card>
    </div>
  );
}
