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

  return (
    <div>
      <PageHeader title={`Holidays ${year}`} subtitle={<Pa>Company holiday calendar.</Pa>} />
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
                      <Badge tone={past ? "slate" : "blue"}>{fmtDate(h.date)}</Badge>
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
