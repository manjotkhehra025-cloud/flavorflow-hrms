import Link from "next/link";
import { db } from "@/lib/db";
import { fmtDate } from "@/lib/utils";
import { Card } from "@/components/ui";
import { AvatarImg } from "@/components/AvatarImg";

/** Staff: who is present / absent / on-leave today (photo tiles with status ring). */
export async function PresenceBoard({ companyId, today }: { companyId: string; today: Date }) {
  const [employees, presentRows, holidayToday] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true },
      orderBy: { firstName: "asc" },
    }),
    db.attendance.findMany({ where: { companyId, date: today }, select: { employeeId: true } }),
    db.holiday.findFirst({ where: { companyId, date: today }, select: { name: true } }),
  ]);

  const presentSet = new Set(presentRows.map((r) => r.employeeId));
  const leaveRows = await db.leaveRequest.findMany({
    where: { companyId, status: "APPROVED", fromDate: { lte: today }, toDate: { gte: today } },
    select: { employeeId: true },
  });
  const leaveSet = new Set(leaveRows.map((l) => l.employeeId));

  const tiles = employees.map((e) => {
    let status: "present" | "leave" | "off" | "absent" = "absent";
    if (presentSet.has(e.id)) status = "present";
    else if (leaveSet.has(e.id)) status = "leave";
    else if (holidayToday || e.weeklyOff === today.getUTCDay()) status = "off";
    return { e, status };
  });
  const presentCount = tiles.filter((t) => t.status === "present").length;
  const leaveCount = tiles.filter((t) => t.status === "leave").length;

  const RING: Record<string, string> = {
    present: "ring-emerald-500",
    absent: "ring-rose-400",
    leave: "ring-amber-400",
    off: "ring-sky-400",
  };

  return (
    <Card className="p-5">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="text-sm font-bold text-slate-900">Team Presence — {fmtDate(today)}</h3>
          <p className="text-xs text-slate-500">
            In today: <b className="text-emerald-600">{presentCount}/{employees.length}</b>
            {leaveCount > 0 && <> · <b className="text-amber-600">{leaveCount} on leave</b></>}
            {holidayToday && <> · 🎉 {holidayToday.name}</>}
          </p>
        </div>
        <div className="flex gap-3 text-[10px] font-medium text-slate-500">
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-emerald-500" /> Present</span>
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-rose-400" /> Absent</span>
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-amber-400" /> Leave</span>
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-sky-400" /> Off</span>
        </div>
      </div>
      {employees.length === 0 ? (
        <p className="rounded-xl bg-slate-50 px-4 py-6 text-center text-sm text-slate-400">No employees yet — add from Team page</p>
      ) : (
        <div className="grid grid-cols-4 gap-3 sm:grid-cols-6 md:grid-cols-8">
          {tiles.map(({ e, status }) => (
            <Link key={e.id} href={`/employees/${e.id}`} className="group flex flex-col items-center gap-1">
              <div className={`rounded-full ring-[3px] ${RING[status]} transition-transform group-hover:scale-105`}>
                <AvatarImg name={`${e.firstName} ${e.lastName}`} photoUrl={e.photoUrl} size="h-12 w-12" />
              </div>
              <span className="w-full truncate text-center text-[10px] font-semibold text-slate-600">
                {e.firstName} {e.lastName.slice(0, 1)}.
              </span>
            </Link>
          ))}
        </div>
      )}
    </Card>
  );
}
