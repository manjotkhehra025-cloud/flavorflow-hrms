import { pht } from "@/lib/i18n";
import { Pa } from "@/components/Pa";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { fmtDate, todayDate } from "@/lib/utils";
import { Card, PageHeader, Badge, inputCls, btnBrand } from "@/components/ui";
import { addHolidayAction, deleteHolidayAction } from "@/actions/holidays";

export const dynamic = "force-dynamic";

export default async function HolidaysPage() {
  const me = await requireUser();
  const staff = me.role !== "EMPLOYEE";
  const year = todayDate().getUTCFullYear();

  const holidays = await db.holiday.findMany({
    where: {
      companyId: me.companyId,
      date: {
        gte: new Date(Date.UTC(year, 0, 1)),
        lte: new Date(Date.UTC(year, 11, 31)),
      },
    },
    orderBy: { date: "asc" },
  });

  const today = todayDate();

  // 🎂 birthdays from employee DOBs (this calendar year)
  const emps = await db.employee.findMany({
    where: { companyId: me.companyId, status: "ACTIVE", dateOfBirth: { not: null } },
    select: { firstName: true, lastName: true, dateOfBirth: true },
    orderBy: { dateOfBirth: "asc" },
  });
  const birthdays = emps
    .map((e) => {
      const dob = e.dateOfBirth!;
      const md = (dob.getUTCMonth() + 1) * 100 + dob.getUTCDate();
      return { md, name: `${e.firstName} ${e.lastName ?? ""}`.trim(), label: `${String(dob.getUTCDate()).padStart(2, "0")} ${dob.toLocaleDateString("en-IN", { month: "short", timeZone: "UTC" })}` };
    })
    .sort((a, b) => a.md - b.md);
  const todayMd = (today.getUTCMonth() + 1) * 100 + today.getUTCDate();
  const upcoming = [...birthdays.filter((b) => b.md >= todayMd), ...birthdays.filter((b) => b.md < todayMd)];

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <PageHeader title={`Holidays ${year}`} subtitle={<Pa>Company holiday calendar.</Pa>} />
        <a href="/api/holidays.ics" download className="rounded-xl bg-[#0a1628] px-3.5 py-2 text-xs font-extrabold text-emerald-300 shadow transition hover:brightness-110">
          📲 <Pa>Sync to phone (.ics)</Pa>
        </a>
      </div>
      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="p-5 lg:col-span-2">
          {holidays.length === 0 ? (
            <p className="text-sm text-slate-500">No holidays added for {year} yet.</p>
          ) : (
            <ul className="divide-y divide-slate-100">
              {holidays.map((h) => {
                const past = h.date < today;
                return (
                  <li key={h.id} className="flex items-center justify-between py-3 text-sm">
                    <span className={past ? "text-slate-400" : "font-medium text-slate-800"}>{h.name}</span>
                    <span className="flex items-center gap-3">
                      <span className="flex items-center gap-1.5">
                        <Badge tone={past ? "slate" : "blue"}>{fmtDate(h.date)}</Badge>
                        {past && <span className="rounded-full bg-slate-100 px-1.5 py-0.5 text-[9px] font-extrabold uppercase text-slate-400">Passed</span>}
                      </span>
                      {staff && (
                        <form action={deleteHolidayAction.bind(null, h.id)}>
                          <button className="text-xs text-red-500 hover:underline">{<Pa>Delete</Pa>}</button>
                        </form>
                      )}
                    </span>
                  </li>
                );
              })}
            </ul>
          )}
          {birthdays.length > 0 && (
            <div className="mt-5 border-t border-slate-100 pt-4">
              <h3 className="mb-2 text-xs font-bold uppercase tracking-wide text-slate-500">{<Pa>Team birthdays</Pa>} 🎂</h3>
              <ul className="space-y-1.5">
                {upcoming.slice(0, 8).map((b, i) => (
                  <li key={i} className={`flex items-center justify-between text-sm ${b.md < todayMd ? "text-slate-400" : "text-slate-700"}`}>
                    <span className="font-medium">🎂 {b.name}</span>
                    <span className="flex items-center gap-2 text-xs text-slate-400">
                      {b.label}
                      {b.md < todayMd && <span className="rounded-full bg-slate-100 px-1.5 py-0.5 text-[9px] font-extrabold uppercase text-slate-400">{<Pa>Passed</Pa>}</span>}
                      {b.md === todayMd && <span className="rounded-full bg-emerald-100 px-1.5 py-0.5 text-[9px] font-extrabold uppercase text-emerald-700">{<Pa>Today! 🎉</Pa>}</span>}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </Card>
        {staff && (
          <Card className="h-fit p-5">
            <h3 className="mb-4 text-sm font-semibold text-slate-900">{<Pa>Add holiday</Pa>}</h3>
            <form action={addHolidayAction} className="space-y-3">
              <input name="name" required placeholder={await pht("e.g. Diwali")} className={inputCls} />
              <input name="date" type="date" required className={inputCls} />
              <button className={btnBrand}>{<Pa>Add</Pa>}</button>
            </form>
          </Card>
        )}
      </div>
    </div>
  );
}
