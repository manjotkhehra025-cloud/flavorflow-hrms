import { Pa } from "@/components/Pa";
import Link from "next/link";
import { requireStaff } from "@/lib/auth";
import { db } from "@/lib/db";
import { getRequestLang, tt } from "@/lib/i18n";
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
          {c} <span className="font-semibold opacity-80">= <Pa>{label}</Pa></span>
        </span>
      ))}
    </div>
  );
}

function ReportRow(props: {
  icon: IconName;
  tone: string;
  title: React.ReactNode;
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
  const lang = await getRequestLang();
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
      <PageHeader title={<Pa>Reports</Pa>} subtitle={<Pa>Registers, summaries & Excel downloads for payroll</Pa>} />

      {/* Month picker */}
      <Card className="flex items-center justify-between gap-3 p-4">
        <Link href={`/reports?month=${shiftMonth(month, -1)}`} className="btn-ghost px-3!" aria-label="Previous month">←</Link>
        <div className="text-center">
          <div className="text-base font-bold text-slate-900">{label}</div>
          <div className="text-[10.5px] font-medium text-slate-400">{<Pa>All monthly reports below use this month</Pa>}</div>
        </div>
        <Link href={`/reports?month=${shiftMonth(month, 1)}`} className="btn-ghost px-3!" aria-label="Next month">→</Link>
      </Card>

      {/* 1 · Monthly register */}
      <Card className="space-y-3 p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-[14px] font-extrabold text-slate-900">{<Pa>Monthly attendance register</Pa>}</div>
            <p className="text-[11px] text-slate-400">{label} · <Pa>days × employees grid · tap a P cell for in-time</Pa></p>
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
        <div className="px-1 text-[11px] font-extrabold uppercase tracking-[0.15em] text-slate-400">{<Pa>More reports</Pa>}</div>

        <ReportRow
          icon="clock"
          tone="bg-red-50 text-red-500"
          title={<Pa>Late-in report</Pa>}
          stat={shiftCount === 0
            ? "Activate with one step: add a shift in Settings →"
            : tt(lang, "{} late check-in(s) in {} · {}-min grace", late.rows.length, label, LATE_GRACE_MINS)}
          viewHref={shiftCount === 0 ? "/settings" : `/reports/late?month=${month}`}
          xlsHref={`/api/reports/late?month=${month}`}
        />
        <ReportRow
          icon="chart"
          tone="bg-amber-50 text-amber-600"
          title={<Pa>Overtime report</Pa>}
          stat={tt(lang, "{} total OT hrs in {} · beyond shift length + approved OT", hoursFmt(ot.totalOt), label)}
          viewHref={`/reports/ot?month=${month}`}
          xlsHref={`/api/reports/ot?month=${month}`}
        />
        <ReportRow
          icon="calendar"
          tone="bg-violet-50 text-violet-600"
          title={<Pa>Leave balance register</Pa>}
          stat={tt(lang, "{} employees · {} leave types · year-to-date snapshot", lbr.rows.length, lbr.types.length)}
          viewHref="/reports/leave-balance"
          xlsHref="/api/reports/leave-balance"
        />
        <ReportRow
          icon="gate"
          tone="bg-blue-50 text-blue-600"
          title={<Pa>Gate pass log</Pa>}
          stat={tt(lang, "{} passes in {} · guards & payroll audit trail", gp.rows.length, label)}
          viewHref={`/reports/gate-pass?month=${month}`}
          xlsHref={`/api/reports/gate-pass?month=${month}`}
        />
      </div>
    </div>
  );
}
