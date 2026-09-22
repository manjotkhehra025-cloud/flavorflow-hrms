import Link from "next/link";
import { requireStaff } from "@/lib/auth";
import { db } from "@/lib/db";
import { currentMonth, shiftMonth, monthRange } from "@/lib/reports";
import { buildLateIn, LATE_GRACE_MINS } from "@/lib/reports2";
import { Card, PageHeader, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";

export const dynamic = "force-dynamic";

export default async function LateReportPage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>;
}) {
  const me = await requireStaff();
  const { month = currentMonth() } = await searchParams;
  const { label } = monthRange(month);
  const { rows } = await buildLateIn(me.companyId, month);
  const shiftCount = await db.shift.count({ where: { companyId: me.companyId } });

  return (
    <div className="space-y-5">
      <PageHeader title="Late-in report" subtitle={`Late check-ins · ${LATE_GRACE_MINS}-minute grace allowed`} />

      <Card className="flex items-center justify-between gap-3 p-4">
        <Link href={`/reports/late?month=${shiftMonth(month, -1)}`} className="btn-ghost px-3!" aria-label="Previous month">←</Link>
        <div className="text-base font-bold text-slate-900">{label}</div>
        <Link href={`/reports/late?month=${shiftMonth(month, 1)}`} className="btn-ghost px-3!" aria-label="Next month">→</Link>
      </Card>

      <Card className="flex items-center justify-between p-4">
        <div>
          <div className="text-2xl font-extrabold text-red-500">{rows.length}</div>
          <div className="text-xs font-medium text-slate-500">late check-ins</div>
        </div>
        <a href={`/api/reports/late?month=${month}`} className="btn-dark">
          <Icon name="download" className="h-4 w-4" /> Excel
        </a>
      </Card>

      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50/80">
                <th className="th">Employee</th>
                <th className="th">Date</th>
                <th className="th text-right">Shift</th>
                <th className="th text-right">Check-in</th>
                <th className="th text-right">Late by</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr><td colSpan={5}>
                  {shiftCount === 0 ? (
                    <EmptyState icon="clock" title="No shifts configured yet" hint="Add a shift in Settings — late-ins will be detected automatically against shift start time" />
                  ) : (
                    <EmptyState icon="check" title="Everyone on time 🎉" hint={`No late check-ins in ${label}`} />
                )}
                </td></tr>
              )}
              {rows.map((r, i) => (
                <tr key={`${r.employeeId}-${r.date}-${i}`} className="border-b border-slate-50 last:border-0 hover:bg-red-50/30">
                  <td className="td">
                    <div className="font-semibold text-slate-800">{r.name}</div>
                    <div className="text-xs text-slate-400">{r.code}{r.department ? ` · ${r.department}` : ""}</div>
                  </td>
                  <td className="td text-slate-600">{r.dayLabel}</td>
                  <td className="td text-right text-slate-500">{r.shiftStart}</td>
                  <td className="td text-right font-semibold text-slate-800">{r.checkIn}</td>
                  <td className="td text-right">
                    <span className="rounded-md bg-red-100 px-2 py-0.5 text-xs font-bold text-red-600">{r.lateByMins} min</span>
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
