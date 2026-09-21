import Link from "next/link";
import { requireStaff } from "@/lib/auth";
import { buildMonthlyAttendance, monthRange, currentMonth, shiftMonth, fmtAvgTime } from "@/lib/reports";
import { Card, PageHeader, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";

export const dynamic = "force-dynamic";

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>;
}) {
  const me = await requireStaff();
  const { month = currentMonth() } = await searchParams;
  const rows = await buildMonthlyAttendance(me.companyId, month);
  const { label } = monthRange(month);

  const totalPresentDays = rows.reduce((s, r) => s + r.present, 0);
  const totalHours = rows.reduce((s, r) => s + r.totalHours, 0);
  const onLeave = rows.reduce((s, r) => s + r.leaveDays, 0);

  return (
    <div className="space-y-5">
      <PageHeader title="Attendance report" subtitle="Monthly summary for payroll & records" />

      {/* Month picker + export */}
      <Card className="flex flex-wrap items-center justify-between gap-3 p-4">
        <div className="flex items-center gap-2">
          <Link href={`/reports?month=${shiftMonth(month, -1)}`} className="btn-ghost px-3!" aria-label="Previous month">←</Link>
          <div className="min-w-36 text-center">
            <div className="text-base font-bold text-slate-900">{label}</div>
          </div>
          <Link href={`/reports?month=${shiftMonth(month, 1)}`} className="btn-ghost px-3!" aria-label="Next month">→</Link>
        </div>
        <a href={`/api/reports/attendance?month=${month}`} className="btn-dark">
          <Icon name="download" className="h-4 w-4" /> Download CSV
        </a>
      </Card>

      {/* Summary chips */}
      <div className="grid grid-cols-3 gap-3 md:gap-4">
        <Card className="p-4 text-center">
          <div className="text-2xl font-extrabold text-slate-900">{rows.length}</div>
          <div className="mt-0.5 text-xs font-medium text-slate-500">Employees</div>
        </Card>
        <Card className="p-4 text-center">
          <div className="text-2xl font-extrabold text-emerald-600">{totalPresentDays}</div>
          <div className="mt-0.5 text-xs font-medium text-slate-500">Total present days</div>
        </Card>
        <Card className="p-4 text-center">
          <div className="text-2xl font-extrabold text-amber-600">{onLeave}</div>
          <div className="mt-0.5 text-xs font-medium text-slate-500">Total leave days</div>
        </Card>
      </div>

      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50/80">
                <th className="th">Employee</th>
                <th className="th text-right">Present</th>
                <th className="th text-right">Leave</th>
                <th className="th text-right">Hours</th>
                <th className="th text-right">Avg in-time</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr><td colSpan={5}><EmptyState icon="chart" title="No employees yet" hint="Add employees to see their monthly report" /></td></tr>
              )}
              {rows.map((r) => (
                <tr key={r.code} className="border-b border-slate-50 transition-colors last:border-0 hover:bg-amber-50/40">
                  <td className="td">
                    <div className="font-semibold text-slate-800">{r.name}</div>
                    <div className="text-xs text-slate-400">{r.code}{r.department ? ` · ${r.department}` : ""}</div>
                  </td>
                  <td className="td text-right">
                    <span className="font-bold text-emerald-600">{r.present}</span>
                    {r.fullDays < r.present && r.fullDays > 0 && (
                      <span className="block text-[10px] text-slate-400">({r.fullDays} full)</span>
                    )}
                  </td>
                  <td className="td text-right font-semibold text-amber-600">{r.leaveDays || "—"}</td>
                  <td className="td text-right font-semibold text-slate-700">{r.totalHours > 0 ? r.totalHours.toFixed(1) : "—"}</td>
                  <td className="td text-right text-slate-600">{fmtAvgTime(r.avgInMins)}</td>
                </tr>
              ))}
              {rows.length > 0 && (
                <tr className="bg-slate-50/80 font-bold">
                  <td className="td text-slate-900">Total</td>
                  <td className="td text-right text-emerald-700">{totalPresentDays}</td>
                  <td className="td text-right text-amber-700">{onLeave}</td>
                  <td className="td text-right text-slate-900">{totalHours.toFixed(1)}</td>
                  <td className="td"></td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>

      <p className="text-xs text-slate-400">
        Hours = check-out minus check-in dono hohan wale dinan de. Leaves = approved requests overlapping the month.
      </p>
    </div>
  );
}
