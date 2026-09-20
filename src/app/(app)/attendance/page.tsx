import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate, fmtDate, fmtTime, initials, toDateOnly } from "@/lib/utils";
import { Card, PageHeader, Badge, btnBrand, btnGhost, inputCls } from "@/components/ui";
import { checkInAction, checkOutAction } from "@/actions/attendance";

export const dynamic = "force-dynamic";

export default async function AttendancePage({
  searchParams,
}: {
  searchParams: Promise<{ date?: string }>;
}) {
  const me = await requireUser();
  const { date: dateParam } = await searchParams;
  const staff = me.role !== "EMPLOYEE";
  const selectedDate = dateParam ? toDateOnly(dateParam) : todayDate();

  const myToday = me.employeeId
    ? await db.attendance.findUnique({
        where: { employeeId_date: { employeeId: me.employeeId, date: todayDate() } },
      })
    : null;

  const dayRows = staff
    ? await db.attendance.findMany({
        where: { companyId: me.companyId, date: selectedDate },
        include: { employee: { include: { department: true } } },
        orderBy: { checkIn: "asc" },
      })
    : [];

  const myHistory = me.employeeId
    ? await db.attendance.findMany({
        where: { employeeId: me.employeeId },
        orderBy: { date: "desc" },
        take: 14,
      })
    : [];

  const activeCount = staff
    ? await db.employee.count({ where: { companyId: me.companyId, status: "ACTIVE" } })
    : 0;

  return (
    <div>
      <PageHeader title="Attendance" subtitle={staff ? "Company view by day, plus your own punches." : "Your check-ins and history."} />

      {me.employeeId && (
        <Card className="mb-6 flex flex-wrap items-center justify-between gap-4 p-5">
          <div>
            <div className="text-sm font-medium text-slate-500">Today · {fmtDate(todayDate())}</div>
            <div className="mt-1 text-lg font-semibold text-slate-900">
              {myToday?.checkIn
                ? `In ${fmtTime(myToday.checkIn)}${myToday.checkOut ? ` · Out ${fmtTime(myToday.checkOut)}` : " · still on duty"}`
                : "Not checked in"}
            </div>
          </div>
          <div className="flex gap-2">
            {!myToday?.checkIn && (
              <form action={checkInAction}><button className={btnBrand}>Check in</button></form>
            )}
            {myToday?.checkIn && !myToday.checkOut && (
              <form action={checkOutAction}><button className={btnGhost}>Check out</button></form>
            )}
          </div>
        </Card>
      )}

      {staff && (
        <Card className="mb-6">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-4">
            <h3 className="text-sm font-semibold text-slate-900">
              {fmtDate(selectedDate)} — {dayRows.length} of {activeCount} present
            </h3>
            <form method="GET" action="/attendance" className="flex items-center gap-2">
              <input type="date" name="date" defaultValue={selectedDate.toISOString().slice(0, 10)} className={inputCls} />
              <button className={btnGhost}>Go</button>
            </form>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                  <th className="px-5 py-3">Employee</th>
                  <th className="px-5 py-3">Department</th>
                  <th className="px-5 py-3">Check in</th>
                  <th className="px-5 py-3">Check out</th>
                  <th className="px-5 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {dayRows.length === 0 && (
                  <tr><td colSpan={5} className="px-5 py-8 text-center text-slate-500">No punches recorded for this day.</td></tr>
                )}
                {dayRows.map((a) => (
                  <tr key={a.id} className="border-b border-slate-100 last:border-0">
                    <td className="px-5 py-3">
                      <span className="flex items-center gap-2">
                        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-slate-100 text-xs font-bold text-slate-600">
                          {initials(`${a.employee.firstName} ${a.employee.lastName}`)}
                        </span>
                        <span className="font-medium text-slate-800">{a.employee.firstName} {a.employee.lastName}</span>
                      </span>
                    </td>
                    <td className="px-5 py-3 text-slate-600">{a.employee.department?.name ?? "—"}</td>
                    <td className="px-5 py-3 text-slate-600">{fmtTime(a.checkIn)}</td>
                    <td className="px-5 py-3 text-slate-600">{fmtTime(a.checkOut)}</td>
                    <td className="px-5 py-3"><Badge tone={a.status === "PRESENT" ? "green" : "amber"}>{a.status}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {me.employeeId && (
        <Card>
          <h3 className="border-b border-slate-200 px-5 py-4 text-sm font-semibold text-slate-900">My last 14 days</h3>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                  <th className="px-5 py-3">Date</th>
                  <th className="px-5 py-3">In</th>
                  <th className="px-5 py-3">Out</th>
                  <th className="px-5 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {myHistory.length === 0 && (
                  <tr><td colSpan={4} className="px-5 py-8 text-center text-slate-500">No records yet — press Check in above.</td></tr>
                )}
                {myHistory.map((a) => (
                  <tr key={a.id} className="border-b border-slate-100 last:border-0">
                    <td className="px-5 py-3 font-medium text-slate-700">{fmtDate(a.date)}</td>
                    <td className="px-5 py-3 text-slate-600">{fmtTime(a.checkIn)}</td>
                    <td className="px-5 py-3 text-slate-600">{fmtTime(a.checkOut)}</td>
                    <td className="px-5 py-3"><Badge tone={a.status === "PRESENT" ? "green" : "amber"}>{a.status}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {!me.employeeId && !staff && (
        <Card className="p-8 text-center text-sm text-slate-500">
          Your login isn't linked to an employee profile yet — ask your admin.
        </Card>
      )}
    </div>
  );
}
