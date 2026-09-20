import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate, fmtDate, fmtTime, initials } from "@/lib/utils";
import { Card, PageHeader, Badge, btnBrand, btnGhost } from "@/components/ui";
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
    <div>
      <PageHeader title={`Hello, ${me.name.split(" ")[0]} 👋`} subtitle={fmtDate(today)} />

      {/* My attendance widget */}
      {me.employeeId && (
        <Card className="mb-6 flex flex-wrap items-center justify-between gap-4 p-5">
          <div>
            <div className="text-sm font-medium text-slate-500">Today's attendance</div>
            <div className="mt-1 text-lg font-semibold text-slate-900">
              {myAttendance?.checkIn
                ? `Checked in at ${fmtTime(myAttendance.checkIn)}${myAttendance.checkOut ? ` · out ${fmtTime(myAttendance.checkOut)}` : ""}`
                : "You haven't checked in yet"}
            </div>
          </div>
          <div className="flex gap-2">
            {!myAttendance?.checkIn && (
              <form action={checkInAction}>
                <button className={btnBrand}>Check in</button>
              </form>
            )}
            {myAttendance?.checkIn && !myAttendance.checkOut && (
              <form action={checkOutAction}>
                <button className={btnGhost}>Check out</button>
              </form>
            )}
          </div>
        </Card>
      )}

      {/* Stats */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Stat label="Active employees" value={employeeCount} />
        <Stat label="Present today" value={presentToday} />
        <Stat label="Pending leaves" value={pendingLeaves} href={staff ? "/leaves" : undefined} />
        <Stat label="Upcoming holidays" value={upcomingHolidays.length} href="/holidays" />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        {staff && <PendingLeaves companyId={me.companyId} />}
        <Card className="p-5">
          <h3 className="mb-3 text-sm font-semibold text-slate-900">Upcoming holidays</h3>
          {upcomingHolidays.length === 0 ? (
            <p className="text-sm text-slate-500">No holidays added yet.</p>
          ) : (
            <ul className="space-y-2">
              {upcomingHolidays.map((h) => (
                <li key={h.id} className="flex items-center justify-between text-sm">
                  <span className="font-medium text-slate-700">{h.name}</span>
                  <Badge tone="blue">{fmtDate(h.date)}</Badge>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      {staff && (
        <div className="mt-6">
          <Link href="/employees/new" className="text-sm font-medium text-amber-600 hover:underline">
            + Add your first employee →
          </Link>
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, href }: { label: string; value: number; href?: string }) {
  const inner = (
    <Card className="p-5 transition-shadow hover:shadow-md">
      <div className="text-3xl font-bold text-slate-900">{value}</div>
      <div className="mt-1 text-sm text-slate-500">{label}</div>
    </Card>
  );
  return href ? <Link href={href}>{inner}</Link> : inner;
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
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-slate-900">Pending leave requests</h3>
        <Link href="/leaves" className="text-xs font-medium text-amber-600 hover:underline">
          View all
        </Link>
      </div>
      {pending.length === 0 ? (
        <p className="text-sm text-slate-500">Nothing waiting for approval 🎉</p>
      ) : (
        <ul className="space-y-3">
          {pending.map((l) => (
            <li key={l.id} className="flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-100 text-xs font-bold text-slate-600">
                {initials(`${l.employee.firstName} ${l.employee.lastName}`)}
              </div>
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-medium text-slate-700">
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
