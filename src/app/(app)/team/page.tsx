import Link from "next/link";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Tt } from "@/components/LangCtx";
import { toDateOnly } from "@/lib/utils";
import { AvatarImg } from "@/components/AvatarImg";
import { TeamBoard } from "@/components/TeamBoard";

export const dynamic = "force-dynamic";

const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

export default async function TeamPage({ searchParams }: { searchParams: Promise<{ dept?: string; tab?: string }> }) {
  const me = await requireStaff();
  const sp = await searchParams;
  const tab = sp.tab === "leaves" ? "leaves" : "board";
  const today = toDateOnly(new Date().toISOString().slice(0, 10));

  const [employees, deps, attToday] = await Promise.all([
    db.employee.findMany({
      where: { companyId: me.companyId, status: "ACTIVE" },
      include: { department: true, shift: true },
      orderBy: [{ department: { name: "asc" } }, { firstName: "asc" }],
    }),
    db.department.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" } }),
    db.attendance.findMany({ where: { companyId: me.companyId, date: today } }),
  ]);
  const attMap = new Map(attToday.map((a) => [a.employeeId, a]));

  const rows = employees
    .filter((e) => !sp.dept || e.departmentId === sp.dept)
    .map((e) => {
      const att = attMap.get(e.id);
      const hasIn = Boolean(att?.checkIn || (att && att.status === "PRESENT"));
      const hasOut = Boolean(att?.checkOut);
      const status: "IN" | "OUT" | "ABSENT" = hasIn ? (hasOut ? "OUT" : "IN") : "ABSENT";
      return {
        id: e.id,
        name: `${e.firstName} ${e.lastName ?? ""}`.trim(),
        dept: e.department?.name ?? "—",
        shift: e.shift ? `${e.shift.name} ${e.shift.startTime}` : "—",
        photo: e.photoUrl,
        status,
        inAt: att?.checkIn ? new Date(att.checkIn).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", hour12: true }) : null,
        outAt: att?.checkOut ? new Date(att.checkOut).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", hour12: true }) : null,
        completed: Boolean(hasIn && hasOut),
        weeklyOff: e.weeklyOff,
      };
    });

  const counts = { in: rows.filter((r) => r.status === "IN").length, out: rows.filter((r) => r.status === "OUT").length, absent: rows.filter((r) => r.status === "ABSENT").length, done: rows.filter((r) => r.completed).length };

  // Upcoming approved leaves (next 14 days)
  const horizon = new Date(today.getTime() + 14 * 86400000);
  const upcomingLeaves = await db.leaveRequest.findMany({
    where: { companyId: me.companyId, status: "APPROVED", toDate: { gte: today }, fromDate: { lt: horizon } },
    include: { employee: { include: { department: true } }, leaveType: true },
    orderBy: { fromDate: "asc" },
  });
  const leaveRows = upcomingLeaves.map((l) => ({
    id: l.id,
    name: `${l.employee.firstName} ${l.employee.lastName ?? ""}`.trim(),
    dept: l.employee.department?.name ?? "—",
    from: new Date(l.fromDate).toLocaleDateString("en-IN", { day: "numeric", month: "short" }),
    to: new Date(l.toDate).toLocaleDateString("en-IN", { day: "numeric", month: "short" }),
    days: l.days,
    type: l.leaveType.name,
  }));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight text-slate-900"><Tt>Live Team</Tt> 👥</h1>
          <p className="text-sm text-slate-500"><Tt>Who's on the floor right now, on a single screen.</Tt></p>
        </div>
        <div className="flex gap-1 rounded-2xl bg-slate-100 p-1">
          <Link href="/team" className={tab === "board" ? "rounded-xl bg-white px-3.5 py-1.5 text-xs font-extrabold text-slate-800 shadow-sm" : "px-3.5 py-1.5 text-xs font-bold text-slate-500"}><Tt>Board</Tt></Link>
          <Link href="/team?tab=leaves" className={tab === "leaves" ? "rounded-xl bg-white px-3.5 py-1.5 text-xs font-extrabold text-slate-800 shadow-sm" : "px-3.5 py-1.5 text-xs font-bold text-slate-500"}><Tt>Upcoming Leaves</Tt>{leaveRows.length > 0 && <span className="ml-1 rounded-full bg-amber-100 px-1.5 text-[10px] font-extrabold text-amber-700">{leaveRows.length}</span>}</Link>
        </div>
      </div>

      {tab === "board" ? (
        <TeamBoard
          rows={rows}
          counts={counts}
          departments={deps.map((d) => ({ id: d.id, name: d.name }))}
          activeDept={sp.dept ?? ""}
          dayNames={DAYS.map((d) => d)}
        />
      ) : (
        <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50 text-[11px] font-extrabold uppercase tracking-wide text-slate-500">
                <th className="px-4 py-2.5"><Tt>Employee</Tt></th><th className="px-4 py-2.5"><Tt>Dates</Tt></th><th className="px-4 py-2.5"><Tt>Days</Tt></th><th className="px-4 py-2.5"><Tt>Type</Tt></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-50">
              {leaveRows.map((l) => (
                <tr key={l.id}>
                  <td className="px-4 py-2.5"><span className="font-bold text-slate-800">{l.name}</span> <span className="text-xs text-slate-400">· {l.dept}</span></td>
                  <td className="px-4 py-2.5 text-slate-600">{l.from} → {l.to}</td>
                  <td className="px-4 py-2.5"><span className="rounded-lg bg-amber-100 px-2 py-0.5 text-xs font-extrabold text-amber-700">{l.days}d</span></td>
                  <td className="px-4 py-2.5 text-slate-600">{l.type}</td>
                </tr>
              ))}
              {leaveRows.length === 0 && <tr><td colSpan={4} className="px-4 py-10 text-center text-sm text-slate-400"><Tt>No approved leaves in the next 14 days 🎉</Tt></td></tr>}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
