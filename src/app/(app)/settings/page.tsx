import { pht } from "@/lib/i18n";
import { Pa } from "@/components/Pa";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { fmtTime } from "@/lib/utils";
import { Card, PageHeader, EmptyState, Badge, btnBrand, inputCls } from "@/components/ui";
import { Icon } from "@/components/icons";
import { createShiftAction, deleteShiftAction, seedFactoryShiftsAction } from "@/actions/shifts";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const me = await requireStaff();

  const [shifts, leaveTypes, empCounts] = await Promise.all([
    db.shift.findMany({
      where: { companyId: me.companyId },
      include: { _count: { select: { employees: true } } },
      orderBy: { startTime: "asc" },
    }),
    db.leaveType.findMany({ where: { companyId: me.companyId }, orderBy: { daysPerYear: "desc" } }),
    db.employee.groupBy({ by: ["category"], where: { companyId: me.companyId, status: "ACTIVE" }, _count: true }),
  ]);

  const yellowCount = empCounts.find((c) => c.category === "YELLOW_CARD")?._count ?? 0;
  const officialCount = empCounts.find((c) => c.category === "OFFICIAL")?._count ?? 0;

  return (
    <div>
      <PageHeader title={<Pa>Settings & Shifts</Pa>} subtitle={<Pa>Factory policy configuration — shifts, leave quotas & staff categories.</Pa>} />

      {/* Company snapshot */}
      <Card className="mb-6 flex flex-wrap items-center justify-between gap-4 border-l-4! border-l-emerald-500! p-5">
        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-400">{<Pa>Company</Pa>}</div>
          <div className="mt-0.5 text-lg font-extrabold text-slate-900">{me.companyName}</div>
        </div>
        <div className="flex gap-2">
          <Badge tone="blue">🔵 Official: {officialCount}</Badge>
          <Badge tone="amber">🟡 Yellow Card: {yellowCount}</Badge>
        </div>
      </Card>

      {/* Shift Management */}
      <Card className="mb-6 p-5">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="text-sm font-bold text-slate-900">{<Pa>Shift Management</Pa>}</h3>
            <p className="text-xs text-slate-500">{<Pa>Configure factory shift rotations — employees punch against these.</Pa>}</p>
          </div>
          <form action={async () => { "use server"; await seedFactoryShiftsAction(); }}>
            <button className="btn-ghost !text-xs">
              <Icon name="plus" className="h-3.5 w-3.5" /> Seed factory defaults
            </button>
          </form>
        </div>

        {shifts.length === 0 ? (
          <EmptyState icon="clock" title={<Pa>No shifts configured</Pa>} hint={<Pa>Use 'Seed factory defaults' for General / Night / Season</Pa>} />
        ) : (
          <ul className="mb-5 space-y-2.5">
            {shifts.map((s) => (
              <li key={s.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-slate-50 px-4 py-3">
                <div className="flex items-center gap-3">
                  <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#0a1628] text-emerald-400">
                    <Icon name="clock" className="h-4.5 w-4.5" />
                  </span>
                  <div>
                    <div className="text-sm font-bold text-slate-800">{s.name}</div>
                    <div className="text-xs text-slate-500"><Pa>Starts</Pa> {s.startTime} · {s.durationH}h · {s._count.employees} <Pa>employee(s)</Pa></div>
                  </div>
                </div>
                <form action={async (fd: FormData) => { "use server"; await deleteShiftAction({}, fd); }}>
                  <input type="hidden" name="id" value={s.id} />
                  <button className="rounded-lg px-2.5 py-1.5 text-xs font-semibold text-red-500 hover:bg-red-50">{<Pa>Delete</Pa>}</button>
                </form>
              </li>
            ))}
          </ul>
        )}

        <form action={async (fd: FormData) => { "use server"; await createShiftAction({}, fd); }} className="rounded-2xl border border-dashed border-slate-300 bg-slate-50/50 p-4">
          <div className="mb-3 text-xs font-bold uppercase tracking-wide text-slate-500">{<Pa>Add a new shift</Pa>}</div>
          <div className="grid gap-3 sm:grid-cols-4">
            <input name="name" placeholder={await pht("e.g. Season Day")} className={`${inputCls} sm:col-span-2`} required />
            <input type="time" name="startTime" className={inputCls} required title="Start time" />
            <input type="number" name="durationH" step="0.5" min="1" max="16" placeholder={await pht("Hours (e.g. 9)")} className={inputCls} required />
          </div>
          <button className={`${btnBrand} mt-3`}>
            <Icon name="plus" className="h-4 w-4" /> Create shift
          </button>
        </form>
      </Card>

      {/* Leave quotas snapshot */}
      <Card className="p-5">
        <h3 className="mb-4 text-sm font-bold text-slate-900">{<Pa>Leave Type Quotas</Pa>}</h3>
        {leaveTypes.length === 0 ? (
          <EmptyState icon="leaf" title={<Pa>No leave types</Pa>} hint={<Pa>Seed factory defaults above adds Earned Leave (15)</Pa>} />
        ) : (
          <ul className="space-y-2">
            {leaveTypes.map((t) => (
              <li key={t.id} className="flex items-center justify-between rounded-xl bg-slate-50 px-4 py-3 text-sm">
                <span className="font-semibold text-slate-700">{t.name}</span>
                <Badge tone={t.daysPerYear === 0 ? "blue" : "green"}>{t.daysPerYear === 0 ? "Unlimited (LOP)" : `${t.daysPerYear} days / year`}</Badge>
              </li>
            ))}
          </ul>
        )}
        <p className="mt-3 text-xs text-slate-400">
          <Pa>🟡 Yellow Card staff receive EL only — 15 days/year, auto-accruing 1.25/month from join month. Adjust individual balances from the employee profile.</Pa>
        </p>
      </Card>
    </div>
  );
}
