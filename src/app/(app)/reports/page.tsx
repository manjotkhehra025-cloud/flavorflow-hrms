import Link from "next/link";
import { requireStaff } from "@/lib/auth";
import { db } from "@/lib/db";
import { currentMonth, shiftMonth, monthRange } from "@/lib/reports";
import {
  buildRegisterGrid,
  buildLateIn,
  buildOt,
  buildLeaveBalanceRegister,
  buildGatePassLog,
  hoursFmt,
  LATE_GRACE_MINS,
} from "@/lib/reports2";
import { RegisterGrid } from "@/components/RegisterGrid";
import { Card, PageHeader } from "@/components/ui";
import { Icon, type IconName } from "@/components/icons";

export const dynamic = "force-dynamic";

function Legend() {
  const items = [
    ["P", "Present", "bg-emerald-100 text-emerald-700"],
    ["A", "Absent", "bg-red-100 text-red-600"],
    ["L", "Leave", "bg-amber-100 text-amber-700"],
    ["W", "Weekly off", "bg-blue-100 text-blue-700"],
    ["H", "Holiday", "bg-violet-100 text-violet-700"],
  ] as const;
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {items.map(([c, label, tone]) => (
        <span key={c} className={`inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[9.5px] font-bold ${tone}`}>
          {c} <span className="font-semibold opacity-80">= {label}</span>
        </span>
      ))}
    </div>
  );
}

function ReportRow(props: {
  icon: IconName;
  tone: string;
  title: string;
  stat: string;
  viewHref: string;
  xlsHref: string;
}) {
  return (
    <Card className="flex items-center gap-3 p-3.5 transition-shadow hover:shadow-md">
      <span className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl ${props.tone}`}>
        <Icon name={props.icon} className="h-5 w-5" />
      </span>
      <div className="min-w-0 flex-1">
        <Link href={props.viewHref} className="text-[13px] font-bold text-slate-900 hover:text-emerald-700 hover:underline">
          {props.title}
        </Link>
        <p className="truncate text-[11px] font-medium text-slate-500">{props.stat}</p>
      </div>
      <a
        href={props.xlsHref}
        className="inline-flex shrink-0 items-center gap-1.5 rounded-lg border border-emerald-200 bg-emerald-50 px-2.5 py-1.5 text-[11px] font-bold text-emerald-700 transition-colors hover:bg-emerald-100"
      >
        <Icon name="download" className="h-3.5 w-3.5" /> Excel
      </a>
    </Card>
  );
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>;
}) {
  const me = await requireStaff();
  const { month = currentMonth() } = await searchParams;
  const { label } = monthRange(month);

  const [grid, late, ot, lbr, gp, shiftCount] = await Promise.all([
    buildRegisterGrid(me.companyId, month),
    buildLateIn(me.companyId, month),
    buildOt(me.companyId, month),
    buildLeaveBalanceRegister(me.companyId),
    buildGatePassLog(me.companyId, month),
    db.shift.count({ where: { companyId: me.companyId } }),
  ]);

  return (
    <div className="space-y-5">
      <PageHeader title="Reports" subtitle="Registers, summaries & Excel downloads for payroll" />

      {/* Month picker */}
      <Card className="flex items-center justify-between gap-3 p-4">
        <Link href={`/reports?month=${shiftMonth(month, -1)}`} className="btn-ghost px-3!" aria-label="Previous month">←</Link>
        <div className="text-center">
          <div className="text-base font-bold text-slate-900">{label}</div>
          <div className="text-[10.5px] font-medium text-slate-400">All monthly reports below use this month</div>
        </div>
        <Link href={`/reports?month=${shiftMonth(month, 1)}`} className="btn-ghost px-3!" aria-label="Next month">→</Link>
      </Card>

      {/* 1 · Monthly register */}
      <Card className="space-y-3 p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-[14px] font-extrabold text-slate-900">Monthly attendance register</div>
            <p className="text-[11px] text-slate-400">{label} · days × employees grid · tap a cell title for in-time</p>
          </div>
          <a href={`/api/reports/register?month=${month}`} className="btn-dark shrink-0 px-3! py-2! text-xs!">
            <Icon name="download" className="h-4 w-4" /> Excel
          </a>
        </div>
        <Legend />
        <RegisterGrid grid={grid} />
      </Card>

      {/* 2–5 · Other reports */}
      <div className="space-y-3">
        <div className="px-1 text-[11px] font-extrabold uppercase tracking-[0.15em] text-slate-400">More reports</div>

        <ReportRow
          icon="clock"
          tone="bg-red-50 text-red-500"
          title="Late-in report"
          stat={shiftCount === 0
            ? "Activate with one step: add a shift in Settings →"
            : `${late.rows.length} late check-in${late.rows.length === 1 ? "" : "s"} in ${label} · ${LATE_GRACE_MINS}-min grace`}
          viewHref={shiftCount === 0 ? "/settings" : `/reports/late?month=${month}`}
          xlsHref={`/api/reports/late?month=${month}`}
        />
        <ReportRow
          icon="chart"
          tone="bg-amber-50 text-amber-600"
          title="Overtime report"
          stat={`${hoursFmt(ot.totalOt)} total OT hrs in ${label} · beyond shift length + approved OT`}
          viewHref={`/reports/ot?month=${month}`}
          xlsHref={`/api/reports/ot?month=${month}`}
        />
        <ReportRow
          icon="calendar"
          tone="bg-violet-50 text-violet-600"
          title="Leave balance register"
          stat={`${lbr.rows.length} employees · ${lbr.types.length} leave types · year-to-date snapshot`}
          viewHref="/reports/leave-balance"
          xlsHref="/api/reports/leave-balance"
        />
        <ReportRow
          icon="gate"
          tone="bg-blue-50 text-blue-600"
          title="Gate pass log"
          stat={`${gp.rows.length} passes in ${label} · guards & payroll audit trail`}
          viewHref={`/reports/gate-pass?month=${month}`}
          xlsHref={`/api/reports/gate-pass?month=${month}`}
        />
      </div>
    </div>
  );
}
