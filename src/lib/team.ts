import { z } from "zod";
import { db } from "@/lib/db";
import { toDateOnly } from "@/lib/utils";

// The plant and the production server use IST. Explicit timezone handling keeps
// the API, web board and a phone in another timezone on the same attendance day.
export const TEAM_TIME_ZONE = "Asia/Kolkata";
export const TEAM_DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

export type TeamRow = {
  id: string;
  name: string;
  dept: string;
  shift: string;
  photo: string | null;
  status: "IN" | "OUT" | "ABSENT";
  inAt: string | null;
  outAt: string | null;
  completed: boolean;
  weeklyOff: number;
};
export type TeamCounts = { in: number; out: number; absent: number; done: number };

export function teamDate(now: Date): Date {
  return toDateOnly(new Intl.DateTimeFormat("en-CA", {
    timeZone: TEAM_TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now));
}

export function teamPresence(att?: { checkIn: Date | null; checkOut: Date | null; status: string } | null) {
  // Preserve the web's legacy PRESENT-without-timestamps behaviour. "Not in
  // yet" is a presence label, not a write to the attendance/leave register.
  const hasIn = Boolean(att?.checkIn || att?.status === "PRESENT");
  const hasOut = Boolean(att?.checkOut);
  const status: TeamRow["status"] = hasIn ? (hasOut ? "OUT" : "IN") : "ABSENT";
  return { status, completed: hasIn && hasOut };
}

export function teamCounts(rows: Pick<TeamRow, "status" | "completed">[]): TeamCounts {
  return rows.reduce((counts, row) => {
    if (row.status === "IN") counts.in++;
    else if (row.status === "OUT") counts.out++;
    else counts.absent++;
    if (row.completed) counts.done++;
    return counts;
  }, { in: 0, out: 0, absent: 0, done: 0 });
}

function punchTime(date: Date | null | undefined) {
  return date ? date.toLocaleTimeString("en-IN", {
    timeZone: TEAM_TIME_ZONE, hour: "2-digit", minute: "2-digit", hour12: true,
  }).toUpperCase() : null;
}

/** Shared by /team and /api/team. Callers must enforce ADMIN/HR access first. */
export async function getTeamSnapshot(companyId: string, departmentId = "", now = new Date()) {
  const today = teamDate(now);
  const horizon = new Date(today.getTime() + 14 * 86_400_000);
  const [employees, departments, attendance, leaves] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE", ...(departmentId ? { departmentId } : {}) },
      select: {
        id: true, firstName: true, lastName: true, weeklyOff: true,
        photoUrl: true, photoExt: true,
        department: { select: { name: true } },
        shift: { select: { name: true, startTime: true } },
      },
      orderBy: [{ department: { name: "asc" } }, { firstName: "asc" }, { id: "asc" }],
    }),
    db.department.findMany({
      where: { companyId }, select: { id: true, name: true }, orderBy: { name: "asc" },
    }),
    db.attendance.findMany({
      where: { companyId, date: today },
      select: { employeeId: true, status: true, checkIn: true, checkOut: true },
    }),
    db.leaveRequest.findMany({
      where: {
        companyId, employee: { companyId }, status: "APPROVED",
        toDate: { gte: today }, fromDate: { lt: horizon },
      },
      select: {
        id: true, fromDate: true, toDate: true, days: true,
        employee: { select: { firstName: true, lastName: true, department: { select: { name: true } } } },
        leaveType: { select: { name: true } },
      },
      orderBy: [{ fromDate: "asc" }, { id: "asc" }],
    }),
  ]);
  const attMap = new Map(attendance.map((a) => [a.employeeId, a]));
  const rows: TeamRow[] = employees.map((e) => {
    const att = attMap.get(e.id);
    return {
      id: e.id,
      name: `${e.firstName} ${e.lastName ?? ""}`.trim(),
      dept: e.department?.name ?? "—",
      shift: e.shift ? `${e.shift.name} ${e.shift.startTime}` : "—",
      photo: e.photoExt ? `/api/photo/${e.id}` : e.photoUrl,
      ...teamPresence(att),
      inAt: punchTime(att?.checkIn),
      outAt: punchTime(att?.checkOut),
      weeklyOff: e.weeklyOff,
    };
  });
  return {
    date: today.toISOString().slice(0, 10),
    asOf: now.toISOString(),
    timeZone: TEAM_TIME_ZONE,
    activeDept: departmentId,
    rows,
    counts: teamCounts(rows),
    departments,
    // Intentionally company-wide, even when the board has a department filter.
    leaves: leaves.map((l) => ({
      id: l.id,
      name: `${l.employee.firstName} ${l.employee.lastName ?? ""}`.trim(),
      dept: l.employee.department?.name ?? "—",
      fromDate: l.fromDate.toISOString().slice(0, 10),
      toDate: l.toDate.toISOString().slice(0, 10),
      days: l.days,
      type: l.leaveType.name,
    })),
  };
}

const weeklyOffSchema = z.object({
  employeeId: z.string().trim().min(1).max(128),
  weeklyOff: z.number().int().min(0).max(6),
}).strict();

/** The same validated, tenant-scoped mutation powers web and mobile. */
export async function updateTeamWeeklyOff(companyId: string, input: unknown) {
  const parsed = weeklyOffSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, status: 400, error: "Choose an employee and a weekly-off day from Sunday to Saturday." } as const;
  }
  const { employeeId, weeklyOff } = parsed.data;
  const result = await db.employee.updateMany({
    where: { id: employeeId, companyId }, data: { weeklyOff },
  });
  if (!result.count) return { ok: false, status: 404, error: "Employee not found." } as const;
  return { ok: true, employeeId, weeklyOff } as const;
}
