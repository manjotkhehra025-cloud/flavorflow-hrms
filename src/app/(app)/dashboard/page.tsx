import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate, fmtDate, fmtTime, initials } from "@/lib/utils";
import { Card, StatCard, Badge, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";
import { checkInAction, checkOutAction } from "@/actions/attendance";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const me = await requireUser();
  const today = todayDate();
  const staff = me.role !== "EMPLOYEE";

  const [employeeCount, presentToday, pendingLeaves, myAttendance, upcomingHolidays] = await Promise.all([
    db.employee.count({ where: { companyId: me.companyId, status: "ACTIVE" } }),
    db.attendance.count({ where: { companyId: me.companyId, date: today, status: "PRESENT" } }),
    db.leaveRequest.count({ where: { companyId: me.companyId, status: "PENDING" } }),
    me.employeeId
      ? db.attendance.findUnique({ where: { employeeId_date: { employeeId: me.employeeId, date: today } } })
      : null,
    db.holiday.findMany({
      where: { companyId: me.companyId, date: { gte: today } },
      orderBy: { date: "asc" },
      take: 4,
    }),
  ]);

  return (
    <div className="space-y-6">
      {/* ===== Hero ===== */}
      <div className="relative overflow-hidden rounded-3xl bg-slate-950 p-6 text-white shadow-[var(--shadow-pop)] md:p-8">
        {/* decorations */}
        <div className="pointer-events-none absolute -right-16 -top-24 h-64 w-64 rounded-full bg-amber-500/25 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-28 -left-10 h-56 w-56 rounded-full bg-amber-500/10 blur-3xl" />
        <svg className="pointer-events-none absolute inset-0 h-full w-full opacity-[0.07]" aria-hidden>
          <defs>
            <pattern id="grid" width="28" height="28" patternUnits="userSpaceOnUse">
              <path d="M28 0H0v28" fill="none" stroke="white" strokeWidth="1" />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#grid)" />
        </svg>

        <div className="relative flex flex-wrap items-center justify-between gap-5">
          <div>
            <p className="text-xs font-semibold uppercase tracking-widest text-amber-400/90">{fmtDate(today)}</p>
            <h1 className="mt-1.5 text-2xl font-extrabold tracking-tight md:text-3xl">
              Hello, {me.name.split(" ")[0]} 👋
            </h1>
            <p className="mt-1 text-sm text-slate-400">
              {staff ? "Sab theek chal riha — ajj da din shubh hove!" : "Have a great day at work!"}
            </p>
          </div>

          {/* attendance quick box */}
          {me.employeeId && (
            <div className="flex items-center gap-4 rounded-2xl bg-white/[0.06] p-4 ring-1 ring-white/10 backdrop-blur">
              <div>
                <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Today</div>
                <div className="mt-0.5 text-sm font-bold text-white">
                  {myAttendance?.checkIn
                    ? `In ${fmtTime(myAttendance.checkIn)}${myAttendance.checkOut ? ` · Out ${fmtTime(myAttendance.checkOut)}` : ""}`
                    : "Not checked in"}
                </div>
              </div>
              {!myAttendance?.checkIn && (
                <form action={checkInAction}>
                  <button className="btn-brand">Check in</button>
                </form>
              )}
              {myAttendance?.checkIn && !myAttendance.checkOut && (
                <form action={checkOutAction}>
                  <button className="btn-ghost border-white/20! bg-white/10! text-white! hover:bg-white/20!">Check out</button>
                </form>
              )}
            </div>
          )}
        </div>
      </div>

      {/* ===== Stats ===== */}
      <div className="grid grid-cols-2 gap-3 md:gap-4 lg:grid-cols-4">
        <StatCard label="Active employees" value={employeeCount} icon="users" tone="amber" href={staff ? "/employees" : undefined} />
        <StatCard label="Present today" value={presentToday} icon="clock" tone="emerald" href="/attendance" />
        <StatCard label="Pending leaves" value={pendingLeaves} icon="leaf" tone="rose" href="/leaves" />
        <StatCard label="Upcoming holidays" value={upcomingHolidays.length} icon="calendar" tone="sky" href="/holidays" />
      </div>

      {/* ===== Quick actions ===== */}
      {staff && (
        <div className="flex flex-wrap gap-3">
          <Link href="/employees/new" className="btn-dark"><Icon name="plus" className="h-4 w-4" /> Add employee</Link>
          <Link href="/holidays" className="btn-ghost"><Icon name="calendar" className="h-4 w-4" /> Add holiday</Link>
          <Link href="/attendance" className="btn-ghost"><Icon name="clock" className="h-4 w-4" /> View attendance</Link>
        </div>
      )}

      {/* ===== Lower grid ===== */}
      <div className="grid gap-6 lg:grid-cols-2">
        {staff && <PendingLeaves companyId={me.companyId} />}
        <Card className="p-5">
          <div className="mb-4 flex items-center justify-between">
            <h3 className="text-sm font-bold text-slate-900">Upcoming holidays</h3>
            <Link href="/holidays" className="text-xs font-semibold text-amber-600 hover:underline">View all</Link>
          </div>
          {upcomingHolidays.length === 0 ? (
            <EmptyState icon="calendar" title="No holidays added yet" hint={staff ? "Add your company holidays so everyone sees them" : undefined} />
          ) : (
            <ul className="space-y-2.5">
              {upcomingHolidays.map((h) => (
                <li key={h.id} className="flex items-center justify-between rounded-xl bg-slate-50 px-4 py-3 text-sm transition hover:bg-slate-100">
                  <span className="font-semibold text-slate-700">{h.name}</span>
                  <Badge tone="blue">{fmtDate(h.date)}</Badge>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}

async function PendingLeaves({ companyId }: { companyId: string }) {
  const pending = await db.leaveRequest.findMany({
    where: { companyId, status: "PENDING" },
    include: { employee: true, leaveType: true },
    orderBy: { createdAt: "asc" },
    take: 5,
  });

  return (
    <Card className="p-5">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-sm font-bold text-slate-900">Pending leave requests</h3>
        <Link href="/leaves" className="text-xs font-semibold text-amber-600 hover:underline">View all</Link>
      </div>
      {pending.length === 0 ? (
        <EmptyState icon="leaf" title="Nothing waiting for approval" hint="New requests will land here" />
      ) : (
        <ul className="space-y-2.5">
          {pending.map((l) => (
            <li key={l.id} className="flex items-center gap-3 rounded-xl bg-slate-50 px-4 py-3 transition hover:bg-slate-100">
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-slate-900 text-xs font-bold text-amber-400">
                {initials(`${l.employee.firstName} ${l.employee.lastName}`)}
              </div>
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-semibold text-slate-800">
                  {l.employee.firstName} {l.employee.lastName}
                </div>
                <div className="text-xs text-slate-500">
                  {l.leaveType.name} · {fmtDate(l.fromDate)} – {fmtDate(l.toDate)} ({l.days}d)
                </div>
              </div>
              <Badge tone="amber">Pending</Badge>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
