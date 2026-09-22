import { requireStaff } from "@/lib/auth";
import { buildLeaveBalanceRegister } from "@/lib/reports2";
import { Card, PageHeader, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";

export const dynamic = "force-dynamic";

export default async function LeaveBalanceReportPage() {
  const me = await requireStaff();
  const { types, rows } = await buildLeaveBalanceRegister(me.companyId);
  const year = new Date().getUTCFullYear();
  const asOf = new Date().toLocaleDateString("en-IN", {
    day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Kolkata",
  });

  return (
    <div className="space-y-5">
      <PageHeader title="Leave balance register" subtitle={`Year ${year} · snapshot as of ${asOf}`} />

      <Card className="flex items-center justify-between p-4">
        <div>
          <div className="text-2xl font-extrabold text-violet-600">{rows.length}</div>
          <div className="text-xs font-medium text-slate-500">employees · {types.length} leave types</div>
        </div>
        <a href="/api/reports/leave-balance" className="btn-dark">
          <Icon name="download" className="h-4 w-4" /> Excel
        </a>
      </Card>

      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50/80">
                <th className="th">Employee</th>
                {types.map((t) => (
                  <th key={t.id} className="th text-right">{t.name}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr><td colSpan={types.length + 1}><EmptyState icon="users" title="No employees yet" hint="Add employees to see leave balances" /></td></tr>
              )}
              {rows.map((r) => {
                const byType = new Map(r.balances.map((b) => [b.leaveTypeId, b]));
                return (
                  <tr key={r.employeeId} className="border-b border-slate-50 last:border-0 hover:bg-violet-50/30">
                    <td className="td">
                      <div className="font-semibold text-slate-800">{r.name}</div>
                      <div className="text-xs text-slate-400">{r.code}{r.department ? ` · ${r.department}` : ""}</div>
                    </td>
                    {types.map((t) => {
                      const b = byType.get(t.id);
                      if (!b) return <td key={t.id} className="td text-right text-slate-300">—</td>;
                      if (t.daysPerYear === 0) {
                        return <td key={t.id} className="td text-right"><span className="text-xs text-slate-500">∞ · used {b.used}</span></td>;
                      }
                      return (
                        <td key={t.id} className="td text-right">
                          <span className={`font-bold ${b.balance > 0 ? "text-emerald-600" : "text-red-500"}`}>{b.balance}</span>
                          <span className="block text-[10px] text-slate-400">of {b.quota} · used {b.used}{b.pending ? ` · ${b.pending} pending` : ""}</span>
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>

      <p className="text-xs text-slate-400">
        YELLOW_CARD staff: Earned Leave accrues at 1.25 days per month (max 15/yr). ∞ = unlimited quota (leave-without-pay).
      </p>
    </div>
  );
}
