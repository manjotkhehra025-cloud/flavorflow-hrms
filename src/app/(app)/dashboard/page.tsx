import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate, fmtDate, fmtTime, initials } from "@/lib/utils";
import { Card, StatCard, Badge, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";
import { checkInAction, checkOutAction } from "@/actions/attendance";
import { LiveTimer } from "@/components/LiveTimer";
import { PresenceBoard } from "@/components/PresenceBoard";
import { LinkAccountCard } from "@/components/LinkAccountCard";
import { AvatarImg } from "@/components/AvatarImg";

export const dynamic = "force-dynamic";

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function greeting(): string {
  const h = new Date().getHours();
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

export default async function DashboardPage() {
  const me = await requireUser();
  const today = todayDate();
  const staff = me.role !== "EMPLOYEE";

  const myEmployee = me.employeeId
    ? await db.employee.findUnique({ where: { id: me.employeeId }, include: { shift: true } })
    : null;

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

  // Star of the Month (all users) + helpdesk signals
  const [latestStar, openTickets, myTicketsForUnread] = await Promise.all([
    db.starAward.findFirst({
      where: { companyId: me.companyId },
      include: { employee: true },
      orderBy: { month: "desc" },
    }),
    staff ? db.ticket.count({ where: { companyId: me.companyId, status: "OPEN" } }) : Promise.resolve(0),
    me.employeeId
      ? db.ticket.findMany({
          where: { companyId: me.companyId, employeeId: me.employeeId },
          select: {
            id: true,
            employeeSeenAt: true,
            replies: { where: { isStaff: true }, orderBy: { createdAt: "desc" }, take: 1 },
          },
        })
      : Promise.resolve([]),
  ]);
  const myUnreadReplies = myTicketsForUnread.filter(
    (t) => t.replies[0] && (!t.employeeSeenAt || t.replies[0].createdAt > t.employeeSeenAt)
  ).length;

  // Staff login without an employee link can't punch — offer a one-time self-link.
  const linkableEmployees = staff && !me.employeeId
    ? await db.employee.findMany({
        where: { companyId: me.companyId, status: "ACTIVE", users: { none: {} } },
        orderBy: { firstName: "asc" },
        select: { id: true, firstName: true, lastName: true, code: true },
      })
    : [];

  const teamWorking = staff ? presentToday : 0;
  const shiftName = myEmployee?.shift?.name ?? "General Day Shift";
  const shiftHours = myEmployee?.shift?.durationH ?? 9;
  const isWeeklyOff = myEmployee ? today.getUTCDay() === myEmployee.weeklyOff : false;

  return (
    <div className="space-y-6">
      {/* ===== Hero ===== */}
      <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-6 text-white shadow-[var(--shadow-pop)] md:p-8">
        <div className="pointer-events-none absolute -right-16 -top-24 h-64 w-64 rounded-full bg-emerald-500/25 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-28 -left-10 h-56 w-56 rounded-full bg-teal-500/10 blur-3xl" />
        <svg className="pointer-events-none absolute inset-0 h-full w-full opacity-[0.07]" aria-hidden>
          <defs>
            <pattern id="grid" width="28" height="28" patternUnits="userSpaceOnUse">
              <path d="M28 0H0v28" fill="none" stroke="white" strokeWidth="1" />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#grid)" />
        </svg>

        <div className="relative">
          <p className="text-xs font-semibold uppercase tracking-widest text-emerald-400/90">{fmtDate(today)}</p>
          <h1 className="mt-1.5 text-2xl font-extrabold tracking-tight md:text-3xl">
            {greeting()}, {me.name.split(" ")[0]}! 👋
          </h1>
          <p className="mt-1 text-sm text-slate-400">
            Welcome to HRMate · {me.companyName}
          </p>
          <div className="mt-4 flex flex-wrap gap-2.5">
            <Link href="/idcard" className="chip-dark hover:bg-white/15">
              <Icon name="badge" className="h-3.5 w-3.5" /> ID Card &amp; Pass
            </Link>
            <Link href="/leaves" className="chip-dark hover:bg-white/15">
              <Icon name="leaf" className="h-3.5 w-3.5" /> Apply Leave
            </Link>
            {isWeeklyOff && (
              <span className="chip-dark !text-sky-300 ring-sky-400/25!">🌴 Weekly off today</span>
            )}
          </div>
        </div>
      </div>

      {/* ===== Star of the Month shine ===== */}
      {latestStar && (
        <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-5 text-white shadow-[var(--shadow-pop)]">
          <div className="pointer-events-none absolute -right-12 -top-14 h-40 w-40 rounded-full bg-amber-400/25 blur-3xl" />
          <div className="relative flex items-center gap-4">
            <div className="rounded-2xl bg-white/5 p-1 ring-1 ring-amber-300/30">
              <AvatarImg
                name={`${latestStar.employee.firstName} ${latestStar.employee.lastName}`}
                photoUrl={latestStar.employee.photoUrl}
                size="h-12 w-12"
                textSize="text-sm"
              />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[10px] font-extrabold uppercase tracking-[0.18em] text-amber-300">
                ⭐ Star of the Month · {(() => { const [y, m] = latestStar.month.split("-").map(Number); return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString("en-IN", { month: "short", year: "numeric" }); })()}
              </p>
              <p className="mt-0.5 truncate text-base font-extrabold">
                {latestStar.employee.firstName} {latestStar.employee.lastName}
              </p>
              {latestStar.note && <p className="mt-0.5 truncate text-xs text-slate-400">{latestStar.note} 🏆</p>}
            </div>
            {staff && (
              <Link href="/star" className="shrink-0 rounded-xl bg-white/10 px-3 py-2 text-xs font-bold text-amber-200 ring-1 ring-amber-300/25 transition hover:bg-white/15 active:scale-95">
                Manage →
              </Link>
            )}
          </div>
        </div>
      )}

      {/* ===== Helpdesk strip ===== */}
      {staff && openTickets > 0 && (
        <Link href="/helpdesk?tab=inbox" className="flex items-center gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 transition hover:bg-amber-100/70 active:scale-[0.99]">
          <span className="text-lg">💬</span>
          <span className="text-sm font-bold text-amber-800">{openTickets} open helpdesk ticket{openTickets > 1 ? "s" : ""} — your team is waiting</span>
          <span className="ml-auto text-xs font-bold text-amber-600">View →</span>
        </Link>
      )}
      {!staff && myUnreadReplies > 0 && (
        <Link href="/helpdesk" className="flex items-center gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 transition hover:bg-emerald-100/70 active:scale-[0.99]">
          <span className="text-lg">💬</span>
          <span className="text-sm font-bold text-emerald-800">You have {myUnreadReplies} helpdesk ticket{myUnreadReplies > 1 ? "s" : ""} with new HR replies!</span>
          <span className="ml-auto text-xs font-bold text-emerald-600">View →</span>
        </Link>
      )}

      {/* ===== Punch 2.0 ===== */}
      {staff && !me.employeeId && (
        <LinkAccountCard
          employees={linkableEmployees.map((e) => ({
            id: e.id,
            label: `${e.firstName} ${e.lastName} · ${e.code}`,
          }))}
        />
      )}
      {me.employeeId && myEmployee && (
        <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-6 text-white shadow-[var(--shadow-pop)]">
          <div className="pointer-events-none absolute -left-20 top-1/2 h-72 w-72 -translate-y-1/2 rounded-full bg-emerald-500/10 blur-3xl" />
          <div className="relative">
            <div className="flex flex-wrap items-center justify-center gap-2.5">
              <span className="chip-dark">
                <Icon name="building" className="h-3.5 w-3.5" /> {me.companyName} · Khadur Sahib Unit
              </span>
            </div>
            <p className="mt-4 text-center text-[11px] font-bold uppercase tracking-[0.2em] text-slate-400">
              {shiftName} ({shiftHours} hours){isWeeklyOff ? " · Weekly-off day" : ""}
            </p>

            <div className="mx-auto mt-6 max-w-xs">
              {myAttendance?.checkIn ? (
                <LiveTimer checkInIso={myAttendance.checkIn.toISOString()} shiftHours={shiftHours} />
              ) : (
                <div className="mx-auto flex h-40 w-40 flex-col items-center justify-center rounded-full border-[9px] border-white/[0.08] text-center">
                  <Icon name="fingerprint" className="h-10 w-10 text-emerald-400/70" />
                  <p className="mt-2 px-6 text-xs font-semibold text-slate-400">
                    {isWeeklyOff ? "Off-day punch allowed" : "Not punched in yet"}
                  </p>
                </div>
              )}
              {myAttendance?.checkIn && (
                <p className="mt-3 text-center text-sm font-medium text-slate-400">
                  Punched In: <span className="font-bold text-white">{fmtTime(myAttendance.checkIn)}</span>
                  {myAttendance.checkOut && (
                    <>
                      {" "}· Out: <span className="font-bold text-emerald-400">{fmtTime(myAttendance.checkOut)}</span>
                    </>
                  )}
                </p>
              )}
            </div>

            <div className="mx-auto mt-6 max-w-xs">
              {!myAttendance?.checkIn && (
                <form action={checkInAction}>
                  <button className="flex w-full items-center justify-center gap-3 rounded-2xl bg-gradient-to-r from-emerald-500 to-emerald-600 py-4 text-base font-bold text-white shadow-[0_10px_30px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-[0.98]">
                    <Icon name="fingerprint" className="h-6 w-6" /> Punch In
                  </button>
                </form>
              )}
              {myAttendance?.checkIn && !myAttendance.checkOut && (
                <form action={checkOutAction}>
                  <button className="flex w-full items-center justify-center gap-3 rounded-2xl bg-gradient-to-r from-emerald-500 to-emerald-600 py-4 text-base font-bold text-white shadow-[0_10px_30px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-[0.98]">
                    <Icon name="fingerprint" className="h-6 w-6" /> Punch Out
                  </button>
                </form>
              )}
              {myAttendance?.checkIn && myAttendance.checkOut && (
                <div className="rounded-2xl bg-emerald-500/10 py-3.5 text-center text-sm font-bold text-emerald-300 ring-1 ring-emerald-400/25">
                  ✓ Shift completed — great work today!
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ===== Stats ===== */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4 md:gap-4">
        <StatCard label="Active employees" value={employeeCount} icon="users" tone="sky" href={staff ? "/employees" : undefined} />
        <StatCard label="Present today" value={presentToday} icon="clock" tone="emerald" href="/attendance" />
        <StatCard label="Pending leaves" value={pendingLeaves} icon="leaf" tone="amber" href="/leaves" />
        <StatCard label="Upcoming holidays" value={upcomingHolidays.length} icon="calendar" tone="rose" href="/holidays" />
      </div>

      {/* ===== Quick actions ===== */}
      {staff && (
        <div className="flex flex-wrap gap-3">
          <Link href="/employees/new" className="btn-dark"><Icon name="plus" className="h-4 w-4" /> Add employee</Link>
          <Link href="/holidays" className="btn-ghost"><Icon name="calendar" className="h-4 w-4" /> Add holiday</Link>
          <Link href="/approvals" className="btn-ghost"><Icon name="check" className="h-4 w-4" /> Approvals hub</Link>
        </div>
      )}

      {/* ===== Team presence (staff) ===== */}
      {staff && <PresenceBoard companyId={me.companyId} today={today} />}

      {/* ===== Lower grid ===== */}
      <div className="grid gap-6 lg:grid-cols-2">
        {staff && <PendingLeaves companyId={me.companyId} />}
        <Card className="p-5">
          <div className="mb-4 flex items-center justify-between">
            <h3 className="text-sm font-bold text-slate-900">Upcoming holidays</h3>
            <Link href="/holidays" className="text-xs font-semibold text-emerald-600 hover:underline">View all</Link>
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
        <Link href="/approvals" className="text-xs font-semibold text-emerald-600 hover:underline">View all</Link>
      </div>
      {pending.length === 0 ? (
        <EmptyState icon="leaf" title="Nothing waiting for approval" hint="New requests will land here" />
      ) : (
        <ul className="space-y-2.5">
          {pending.map((l) => (
            <li key={l.id} className="flex items-center gap-3 rounded-xl bg-slate-50 px-4 py-3 transition hover:bg-slate-100">
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#0a1628] text-xs font-bold text-emerald-400">
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
