import { Pa } from "@/components/Pa";
import Link from "next/link";
import { requireStaff } from "@/lib/auth";
import { currentMonth, shiftMonth, monthRange } from "@/lib/reports";
import { buildOt, hoursFmt } from "@/lib/reports2";
import { Card, PageHeader, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";

export const dynamic = "force-dynamic";

export default async function OtReportPage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>;
}) {
  const me = await requireStaff();
  const { month = currentMonth() } = await searchParams;
  const { label } = monthRange(month);
  const { rows, totalOt } = await buildOt(me.companyId, month);

  return (
    <div className="space-y-5">
      <PageHeader title={<Pa>Overtime report</Pa>} subtitle={<Pa>Hours worked beyond shift length · plus approved OT requests</Pa>} />

      <Card className="flex items-center justify-between gap-3 p-4">
        <Link href={`/reports/ot?month=${shiftMonth(month, -1)}`} className="btn-ghost px-3!" aria-label="Previous month">←</Link>
        <div className="text-base font-bold text-slate-900">{label}</div>
        <Link href={`/reports/ot?month=${shiftMonth(month, 1)}`} className="btn-ghost px-3!" aria-label="Next month">→</Link>
      </Card>

      <Card className="flex items-center justify-between p-4">
        <div>
          <div className="text-2xl font-extrabold text-amber-600">{hoursFmt(totalOt)} <span className="text-sm">{<Pa>hrs</Pa>}</span></div>
          <div className="text-xs font-medium text-slate-500">total overtime · {rows.length} entries</div>
        </div>
        <a href={`/api/reports/ot?month=${month}`} className="btn-dark">
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
                <th className="th text-right">{<Pa>Worked</Pa>}</th>
                <th className="th text-right">{<Pa>OT hrs</Pa>}</th>
                <th className="th text-right">{<Pa>Source</Pa>}</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr><td colSpan={5}><EmptyState icon="chart" title={<Pa>No overtime this month</Pa>} hint={`No OT hours recorded in ${label}`} /></td></tr>
              )}
              {rows.map((r, i) => (
                <tr key={`${r.employeeId}-${r.date}-${r.source}-${i}`} className="border-b border-slate-50 last:border-0 hover:bg-amber-50/40">
                  <td className="td">
                    <div className="font-semibold text-slate-800">{r.name}</div>
                    <div className="text-xs text-slate-400">{r.code}{r.department ? ` · ${r.department}` : ""}</div>
                  </td>
                  <td className="td text-slate-600">{r.dayLabel}</td>
                  <td className="td text-right text-slate-600">
                    {r.workedHours === null ? "—" : `${hoursFmt(r.workedHours)} / ${hoursFmt(r.shiftHours!)}`}
                  </td>
                  <td className="td text-right">
                    <span className="rounded-md bg-amber-100 px-2 py-0.5 text-xs font-bold text-amber-700">+{hoursFmt(r.otHours)}</span>
                  </td>
                  <td className="td text-right text-[11px] font-semibold text-slate-500">
                    {r.source === "PUNCH" ? "Punch" : "Approved OT"}
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
