import { pht } from "@/lib/i18n";
import { Pa } from "@/components/Pa";
import { savePayRulesAction, saveGeofenceAction } from "@/actions/config";
import { GeofenceCard } from "./GeofenceCard";
import { ShiftRow } from "./ShiftRow";
import { ChangePasswordCard } from "@/components/PasswordCards";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { fmtTime } from "@/lib/utils";
import { Card, PageHeader, EmptyState, Badge, btnBrand, inputCls } from "@/components/ui";
import { Icon } from "@/components/icons";
import { createShiftAction, deleteShiftAction, seedFactoryShiftsAction } from "@/actions/shifts";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const me = await requireStaff();

  const companyRules = await db.company.findUnique({ where: { id: me.companyId }, select: { dailyPaidLeaveDays: true, lateGraceMins: true, latesPerCut: true, daPercent: true, otMultiplier: true, shiftHours: true, punchSelfieRequired: true, geofenceEnabled: true, geoLat: true, geoLng: true, geoRadius: true, geoFacility: true, geoAddress: true } });
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

      <ChangePasswordCard />

      <GeofenceCard initial={{
        enabled: companyRules?.geofenceEnabled ?? false,
        lat: companyRules?.geoLat ?? null,
        lng: companyRules?.geoLng ?? null,
        radius: companyRules?.geoRadius ?? 200,
        facility: companyRules?.geoFacility ?? null,
        address: companyRules?.geoAddress ?? null,
      }} />

      {/* Pay rules (payroll engine) */}
      <Card className="mb-6 p-5">
        <div className="mb-3">
          <h3 className="text-sm font-bold text-slate-900"><Pa>Pay rules ⚖️</Pa> <span className="text-[10px] font-semibold text-slate-400">(<Pa>used by payroll</Pa>)</span></h3>
        </div>
        <form action={async (fd: FormData) => { "use server"; await savePayRulesAction({}, fd); }} className="flex flex-wrap items-end gap-3">
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Pa>Paid leave / year — daily-rate workers</Pa></span>
            <input type="number" name="dailyPaidLeaveDays" min={0} max={30} defaultValue={companyRules?.dailyPaidLeaveDays ?? 0} className="input w-28" />
            <p className="mt-1 text-[10px] text-slate-400"><Pa>0 = leave without pay (default)</Pa></p>
          </label>
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Pa>Late-grace (minutes)</Pa></span>
            <input type="number" name="lateGraceMins" min={0} max={60} defaultValue={companyRules?.lateGraceMins ?? 15} className="input w-24" />
          </label>
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Pa>Every N lates = 1 LOP</Pa></span>
            <input type="number" name="latesPerCut" min={0} max={20} defaultValue={companyRules?.latesPerCut ?? 0} className="input w-24" />
            <p className="mt-1 text-[10px] text-slate-400"><Pa>0 = off</Pa></p>
          </label>
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Pa>OT multiplier ×</Pa></span>
            <input type="number" name="otMultiplier" step="0.25" min="1" max="3" defaultValue={Number(companyRules?.otMultiplier) || 1.5} className="input w-24" />
          </label>
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Pa>DA % (monthly staff)</Pa></span>
            <input type="number" name="daPercent" min={0} max={50} defaultValue={companyRules?.daPercent ?? 0} className="input w-24" />
            <p className="mt-1 text-[10px] text-slate-400"><Pa>0 = no DA</Pa></p>
          </label>
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Pa>Shift hours / day</Pa></span>
            <input type="number" name="shiftHours" step="0.5" min={4} max={12} defaultValue={Number(companyRules?.shiftHours) || 9} className="input w-24" />
          </label>
          <label className="flex items-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-700">
            <input type="checkbox" name="punchSelfieRequired" defaultChecked={companyRules?.punchSelfieRequired ?? false} />
            <Pa>Selfie punch camera (every punch needs a photo)</Pa>
          </label>
          <button type="submit" className={btnBrand}><Pa>Save rules</Pa></button>
        </form>
      </Card>

      {/* Company snapshot */}
      <Card className="mb-6 flex flex-wrap items-center justify-between gap-4 border-l-4! border-l-emerald-500! p-5">
        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-400">{<Pa>Company</Pa>}</div>
          <div className="mt-0.5 text-lg font-extrabold text-slate-900">{me.companyName}</div>
        </div>
        <div className="flex gap-2">
          <Badge tone="blue">Official: {officialCount}</Badge>
          <Badge tone="amber">Yellow Card: {yellowCount}</Badge>
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
              <ShiftRow key={s.id} id={s.id} name={s.name} startTime={s.startTime} durationH={s.durationH} count={s._count.employees} />
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
          <Pa>Yellow Card staff receive EL only — 15 days/year, auto-accruing 1.25/month from join month. Adjust individual balances from the employee profile.</Pa>
        </p>
      </Card>
    </div>
  );
}
