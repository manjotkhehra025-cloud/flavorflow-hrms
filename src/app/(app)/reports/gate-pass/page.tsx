import { Pa } from "@/components/Pa";
import Link from "next/link";
import { requireStaff } from "@/lib/auth";
import { currentMonth, shiftMonth, monthRange } from "@/lib/reports";
import { buildGatePassLog } from "@/lib/reports2";
import { Card, PageHeader, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";

export const dynamic = "force-dynamic";

const STATUS_TONE: Record<string, string> = {
  PENDING: "bg-amber-100 text-amber-700",
  APPROVED: "bg-emerald-100 text-emerald-700",
  REJECTED: "bg-red-100 text-red-600",
};

export default async function GatePassLogPage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>;
}) {
  const me = await requireStaff();
  const { month = currentMonth() } = await searchParams;
  const { label } = monthRange(month);
  const { rows } = await buildGatePassLog(me.companyId, month);

  return (
    <div className="space-y-5">
      <PageHeader title={<Pa>Gate pass log</Pa>} subtitle={<Pa>All exit passes · guards & payroll audit trail</Pa>} />

      <Card className="flex items-center justify-between gap-3 p-4">
        <Link href={`/reports/gate-pass?month=${shiftMonth(month, -1)}`} className="btn-ghost px-3!" aria-label="Previous month">←</Link>
        <div className="text-base font-bold text-slate-900">{label}</div>
        <Link href={`/reports/gate-pass?month=${shiftMonth(month, 1)}`} className="btn-ghost px-3!" aria-label="Next month">→</Link>
      </Card>

      <Card className="flex items-center justify-between p-4">
        <div>
          <div className="text-2xl font-extrabold text-blue-600">{rows.length}</div>
          <div className="text-xs font-medium text-slate-500">{<Pa>gate passes</Pa>}</div>
        </div>
        <a href={`/api/reports/gate-pass?month=${month}`} className="btn-dark">
          <Icon name="download" className="h-4 w-4" /> Excel
        </a>
      </Card>

      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50/80">
                <th className="th">{<Pa>Employee</Pa>}</th>
                <th className="th">{<Pa>Date</Pa>}</th>
                <th className="th text-right">{<Pa>Exit</Pa>}</th>
                <th className="th text-right">{<Pa>Return</Pa>}</th>
                <th className="th">{<Pa>Reason</Pa>}</th>
                <th className="th text-right">{<Pa>Status</Pa>}</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr><td colSpan={6}><EmptyState icon="gate" title={<Pa>No gate passes</Pa>} hint={`Nobody left through the gate in ${label}`} /></td></tr>
              )}
              {rows.map((r) => (
                <tr key={r.id} className="border-b border-slate-50 last:border-0 hover:bg-blue-50/30">
                  <td className="td">
                    <div className="font-semibold text-slate-800">{r.name}</div>
                    <div className="text-xs text-slate-400">{r.code}{r.department ? ` · ${r.department}` : ""}</div>
                  </td>
                  <td className="td text-slate-600">{r.dayLabel}</td>
                  <td className="td text-right font-semibold text-slate-800">{r.exitAt}</td>
                  <td className="td text-right text-slate-600">
                    {r.returnAt ?? "—"}
                    {r.verified && <Icon name="check" className="ml-1 inline h-3.5 w-3.5 text-emerald-600" />}
                  </td>
                  <td className="td max-w-40 truncate text-xs text-slate-500">{r.reason ?? "—"}</td>
                  <td className="td text-right">
                    <span className={`rounded-md px-2 py-0.5 text-[10px] font-bold ${STATUS_TONE[r.status] ?? "bg-slate-100 text-slate-600"}`}>
                      {r.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
