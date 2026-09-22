import { Pa } from "@/components/Pa";
import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate, fmtDate, fmtTime, initials, toDateOnly, cx } from "@/lib/utils";
import { Card, PageHeader, Badge, EmptyState } from "@/components/ui";
import { checkInAction, checkOutAction } from "@/actions/attendance";
import { PunchWithSelfie } from "@/components/PunchWithSelfie";
import { Icon } from "@/components/icons";
import { RequestPunchForm } from "./RequestPunchForm";
import { monthRange, currentMonth, shiftMonth } from "@/lib/reports";

export const dynamic = "force-dynamic";

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const DOW_SHORT = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

function hoursText(a: Date | null, b: Date | null): string | null {
  if (!a || !b) return null;
  const mins = Math.round((b.getTime() - a.getTime()) / 60000);
  if (mins <= 0) return null;
  return `${Math.floor(mins / 60)}h ${mins % 60}m`;
}
function hoursMins(a: Date | null, b: Date | null): number {
  if (!a || !b) return 0;
  return Math.max(0, Math.round((b.getTime() - a.getTime()) / 60000));
}

export default async function AttendancePage({
  searchParams,
}: {
  searchParams: Promise<{ date?: string; m?: string }>;
}) {
  const me = await requireUser();
  const { date: dateParam, m: monthParam } = await searchParams;
  const staff = me.role !== "EMPLOYEE";
  const selectedDate = dateParam ? toDateOnly(dateParam) : todayDate();
  const month = monthParam ?? currentMonth();
  const { start, endExclusive } = monthRange(month);
  const end = new Date(endExclusive.getTime() - 86400000);

  const emp = me.employeeId
    ? await db.employee.findUnique({ where: { id: me.employeeId } })
    : null;

  const myToday = emp
    ? await db.attendance.findUnique({
        where: { employeeId_date: { employeeId: emp.id, date: todayDate() } },
      })
    : null;
  const company = await db.company.findUnique({ where: { id: me.companyId }, select: { punchSelfieRequired: true } });
  const selfieOn = !!company?.punchSelfieRequired;

  const dayRows = staff
    ? await db.attendance.findMany({
        where: { companyId: me.companyId, date: selectedDate },
        include: { employee: { include: { department: true } } },
        orderBy: { checkIn: "asc" },
      })
    : [];

  const activeCount = staff
    ? await db.employee.count({ where: { companyId: me.companyId, status: "ACTIVE" } })
    : 0;

  // --- my month data for calendar ---
  const [myMonthRows, holidays, myLeaves, myRequests] = emp
    ? await Promise.all([
        db.attendance.findMany({ where: { employeeId: emp.id, date: { gte: start, lte: end } } }),
        db.holiday.findMany({ where: { companyId: me.companyId, date: { gte: start, lte: end } } }),
        db.leaveRequest.findMany({
          where: { employeeId: emp.id, status: "APPROVED", fromDate: { lte: end }, toDate: { gte: start } },
        }),
        db.punchRequest.findMany({ where: { employeeId: emp.id }, orderBy: { createdAt: "desc" }, take: 6 }),
      ])
    : [[], [], [], []];

  const mYear = start.getUTCFullYear();
  const mMon = start.getUTCMonth();
  const daysInMonth = new Date(Date.UTC(mYear, mMon + 1, 0)).getUTCDate();
  const firstDow = new Date(Date.UTC(mYear, mMon, 1)).getUTCDay();
  const today = todayDate();

  const attendMap = new Map(myMonthRows.map((a) => [a.date.toISOString().slice(0, 10), a]));
  const holidaySet = new Set(holidays.map((h) => h.date.toISOString().slice(0, 10)));
  const leaveSet = new Set<string>();
  for (const l of myLeaves) {
    for (let d = new Date(l.fromDate); d <= l.toDate; d = new Date(d.getTime() + 86400000)) {
      leaveSet.add(d.toISOString().slice(0, 10));
    }
  }

  type Dot = { day: number; iso: string; kind: "present" | "off" | "holiday" | "leave" | "absent" | "none" | "today-nothing"; isToday: boolean };
  const dots: Dot[] = [];
  for (let d = 1; d <= daysInMonth; d++) {
    const date = new Date(Date.UTC(mYear, mMon, d));
    const iso = date.toISOString().slice(0, 10);
    const isToday = date.getTime() === today.getTime();
    let kind: Dot["kind"] = "none";
    const row = attendMap.get(iso);
    if (row?.checkIn) kind = "present";
    else if (holidaySet.has(iso)) kind = "holiday";
    else if (leaveSet.has(iso)) kind = "leave";
    else if (emp && date.getUTCDay() === emp.weeklyOff) kind = "off";
    else if (date.getTime() < today.getTime()) kind = "absent";
    else if (isToday) kind = "today-nothing";
    dots.push({ day: d, iso, kind, isToday });
  }

  const DOT_STYLE: Record<string, string> = {
    present: "bg-emerald-500",
    off: "bg-sky-500",
    holiday: "bg-amber-400",
    leave: "bg-amber-400",
    absent: "bg-rose-500",
    none: "bg-transparent",
    "today-nothing": "bg-transparent",
  };

  const monthLabel = start.toLocaleDateString("en-IN", { month: "long", year: "numeric", timeZone: "UTC" });
  const monthlyRows = [...myMonthRows].sort((a, b) => (a.date < b.date ? -1 : 1)).reverse();

  return (
    <div>
      <PageHeader title={<Pa>Attendance & Logs</Pa>} subtitle={staff ? <Pa>Your calendar + team daily view, manual punches & OT.</Pa> : <Pa>Your calendar, punch records & manual punch requests.</Pa>} />

      {/* Today's punch */}
      {emp && (
        <Card className="mb-6 flex flex-wrap items-center justify-between gap-4 border-l-4! border-l-emerald-500! p-5">
          <div>
            <div className="text-sm font-medium text-slate-500">
              <Pa>Today</Pa> · {fmtDate(todayDate())} · <Pa>Weekly off</Pa>: <Pa>{WEEKDAYS[emp.weeklyOff]}</Pa>
            </div>
            <div className="mt-1 text-lg font-semibold text-slate-900">
              {myToday?.checkIn
                ? `In ${fmtTime(myToday.checkIn)}${myToday.checkOut ? ` · Out ${fmtTime(myToday.checkOut)} · ${hoursText(myToday.checkIn, myToday.checkOut) ?? ""}` : " · still on duty"}`
                : todayDate().getUTCDay() === emp.weeklyOff
                  ? "Weekly off — punches optional"
                  : "Not punched in yet"}
            </div>
          </div>
          <div className="flex gap-2">
            {!selfieOn && !myToday?.checkIn && (
              <form action={checkInAction}>
                <button className="btn-brand"><Icon name="fingerprint" className="h-4 w-4" />{<Pa>Punch in</Pa>}</button>
              </form>
            )}
            {!selfieOn && myToday?.checkIn && !myToday.checkOut && (
              <form action={checkOutAction}>
                <button className="btn-ghost"><Icon name="fingerprint" className="h-4 w-4" />{<Pa>Punch out</Pa>}</button>
              </form>
            )}
          </div>
        </Card>
      )}

      {/* Month calendar (own) */}
      {emp && (
        <Card className="mb-6 p-5">
          <div className="mb-3 flex items-center justify-between">
            <h3 className="text-sm font-bold text-slate-900">📅 {monthLabel}</h3>
            <div className="flex gap-1">
              <Link href={`/attendance?m=${shiftMonth(month, -1)}${dateParam ? `&date=${dateParam}` : ""}`} className="btn-ghost px-3 py-1 text-sm">‹</Link>
              <Link href={`/attendance?m=${shiftMonth(month, 1)}${dateParam ? `&date=${dateParam}` : ""}`} className="btn-ghost px-3 py-1 text-sm">›</Link>
            </div>
          </div>
          <div className="grid grid-cols-7 gap-1 text-center">
            {DOW_SHORT.map((d) => (
              <div key={d} className="py-1 text-[10px] font-bold tracking-wide text-slate-400"><Pa>{d}</Pa></div>
            ))}
            {Array.from({ length: firstDow }).map((_, i) => (
              <div key={`b${i}`} />
            ))}
            {dots.map((dot) => (
              <div
                key={dot.iso}
                className={cx(
                  "relative flex h-9 items-center justify-center rounded-lg text-xs font-semibold text-slate-600",
                  dot.isToday && "ring-2 ring-emerald-500 font-black text-emerald-700 bg-emerald-50"
                )}
              >
                {dot.day}
                {DOT_STYLE[dot.kind] !== "bg-transparent" && (
                  <span className={cx("absolute bottom-1 h-1.5 w-1.5 rounded-full", DOT_STYLE[dot.kind])} />
                )}
              </div>
            ))}
          </div>
          <div className="mt-4 flex flex-wrap gap-x-4 gap-y-1.5 text-[11px] font-medium text-slate-500">
            <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-emerald-500" />{<Pa>Present</Pa>}</span>
            <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-sky-500" />{<Pa>Weekly Off</Pa>}</span>
            <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-amber-400" />{<Pa>Holiday / Leave</Pa>}</span>
            <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-rose-500" />{<Pa>Absent</Pa>}</span>
          </div>
        </Card>
      )}

      {/* Manual punch / OT request forms */}
      {emp && <RequestPunchForm recent={myRequests.map((r) => ({ id: r.id, type: r.type, date: r.date, time: r.time, hours: r.hours, status: r.status }))} />}

      {/* Monthly log table (own) */}
      {emp && monthlyRows.length > 0 && (
        <Card className="mb-6 overflow-hidden">
          <div className="border-b border-slate-100 p-5 pb-4">
            <h3 className="text-sm font-bold text-slate-900">{<Pa>Monthly Attendance Logs</Pa>}</h3>
            <p className="text-xs text-slate-500">Detailed day-by-day record · {monthLabel}</p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-100">
                  <th className="th">{<Pa>Date</Pa>}</th>
                  <th className="th">{<Pa>Status</Pa>}</th>
                  <th className="th">{<Pa>Punch in</Pa>}</th>
                  <th className="th">{<Pa>Punch out</Pa>}</th>
                  <th className="th">{<Pa>Hours</Pa>}</th>
                </tr>
              </thead>
              <tbody>
                {monthlyRows.map((r) => {
                  const mins = hoursMins(r.checkIn, r.checkOut);
                  return (
                    <tr key={r.id} className="border-b border-slate-50 transition hover:bg-slate-50/60">
                      <td className="td font-medium text-slate-700">{fmtDate(r.date)}</td>
                      <td className="td">
                        {mins > 0 && mins < 360 ? (
                          <Badge tone="amber">{<Pa>Half day</Pa>}</Badge>
                        ) : (
                          <Badge tone="green">{r.status === "PRESENT" ? "Present" : r.status}</Badge>
                        )}
                      </td>
                      <td className="td text-slate-600">{fmtTime(r.checkIn)}</td>
                      <td className="td text-slate-600">{fmtTime(r.checkOut)}</td>
                      <td className="td font-semibold text-slate-700">{hoursText(r.checkIn, r.checkOut) ?? "—"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* Staff: team daily view */}
      {staff && (
        <Card className="overflow-hidden">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 p-5 pb-4">
            <div>
              <h3 className="text-sm font-bold text-slate-900">{<Pa>Team daily view</Pa>}</h3>
              <p className="text-xs text-slate-500">
                {fmtDate(selectedDate)} · Present {dayRows.length} / {activeCount}
              </p>
            </div>
            <form>
              <input type="hidden" name="m" value={month} />
              <div className="flex items-center gap-2">
                <input type="date" name="date" defaultValue={selectedDate.toISOString().slice(0, 10)} className="input !w-auto !py-1.5" />
                <button className="btn-ghost !py-1.5">{<Pa>Go</Pa>}</button>
              </div>
            </form>
          </div>
          {dayRows.length === 0 ? (
            <div className="p-6"><EmptyState icon="clock" title={<Pa>No punches on this day</Pa>} hint={<Pa>Try another date</Pa>} /></div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-100">
                    <th className="th">{<Pa>Employee</Pa>}</th>
                    <th className="th">{<Pa>Department</Pa>}</th>
                    <th className="th">{<Pa>Photo</Pa>}</th>
                    <th className="th">{<Pa>In</Pa>}</th>
                    <th className="th">{<Pa>Out</Pa>}</th>
                    <th className="th">{<Pa>Hours</Pa>}</th>
                  </tr>
                </thead>
                <tbody>
                  {dayRows.map((r) => (
                    <tr key={r.id} className="border-b border-slate-50 transition hover:bg-slate-50/60">
                      <td className="td">
                        <Link href={`/employees/${r.employeeId}`} className="flex items-center gap-2.5 font-medium text-slate-800 hover:text-emerald-700">
                          <span className="flex h-8 w-8 items-center justify-center rounded-full bg-[#0a1628] text-[10px] font-bold text-emerald-400">
                            {initials(`${r.employee.firstName} ${r.employee.lastName}`)}
                          </span>
                          {r.employee.firstName} {r.employee.lastName}
                        </Link>
                      </td>
                      <td className="td text-slate-500">{r.employee.department?.name ?? "—"}</td>
                      <td className="td">
                        {r.selfiePath ? (
                          <a href={r.selfiePath} target="_blank" rel="noreferrer" title="View punch selfie">
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img src={r.selfiePath} alt="selfie" className="h-8 w-8 rounded-lg object-cover ring-1 ring-slate-200" />
                          </a>
                        ) : <span className="text-slate-300">—</span>}
                      </td>
                      <td className="td text-slate-600">{fmtTime(r.checkIn)}</td>
                      <td className="td text-slate-600">{fmtTime(r.checkOut)}</td>
                      <td className="td font-semibold text-slate-700">{hoursText(r.checkIn, r.checkOut) ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </div>
  );
}
