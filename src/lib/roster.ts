import { z } from "zod";
import { db } from "@/lib/db";
import { getPerms } from "@/lib/permissions";
import { toDateOnly } from "@/lib/utils";

export const ROSTER_TIME_ZONE = "Asia/Kolkata";
export const ROSTER_EMPLOYEE_CAP = 120;
const DAY = 86_400_000;

export type RosterCell = { shiftId: string; isOff: boolean };
export type RosterShift = { id: string; name: string; startTime: string; durationH: number };
export type RosterEmployee = {
  id: string;
  code: string;
  name: string;
  dept: string;
  deptId: string;
  defShift: string | null;
  defStart: string | null;
  cells: Record<string, RosterCell>;
};
export type RosterSwap = {
  id: string;
  requester: string;
  peer: string;
  date: string;
  note: string | null;
  status: "PENDING" | "APPROVED" | "REJECTED" | "CANCELLED";
  mine: boolean;
};
export type RosterPeer = { id: string; name: string; code: string; department: string | null };

export function rosterDate(now: Date): Date {
  return toDateOnly(new Intl.DateTimeFormat("en-CA", {
    timeZone: ROSTER_TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now));
}

export function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function isIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = toDateOnly(value);
  return !Number.isNaN(date.getTime()) && isoDate(date) === value;
}

/** Monday of the week containing a date-only UTC timestamp. */
export function mondayOf(day: Date): Date {
  const delta = (day.getUTCDay() + 6) % 7;
  return new Date(day.getTime() - delta * DAY);
}

export function weekDays(monday: Date): Date[] {
  return Array.from({ length: 7 }, (_, i) => new Date(monday.getTime() + i * DAY));
}

export function parseRosterWeek(week: string | null | undefined, now = new Date()): Date | null {
  if (!week) return mondayOf(rosterDate(now));
  if (!isIsoDate(week)) return null;
  return mondayOf(toDateOnly(week));
}

function personName(first: string, last?: string | null) {
  return `${first} ${last ?? ""}`.trim();
}

/** Shared by web /roster and GET /api/roster/staff. Callers must enforce ADMIN/HR first. */
export async function getStaffRoster(
  companyId: string,
  opts: { week?: string | null; now?: Date; viewerEmployeeId?: string | null } = {},
) {
  const now = opts.now ?? new Date();
  const monday = parseRosterWeek(opts.week ?? null, now);
  if (!monday) return { ok: false as const, status: 400, error: "Invalid week." };
  const days = weekDays(monday);
  const from = days[0];
  const to = days[6];
  const viewerEmployeeId = opts.viewerEmployeeId ?? null;

  const [employees, shifts, assignments, departments, swapsRaw, peers, perms] = await Promise.all([
    db.employee.findMany({
      where: { companyId, status: "ACTIVE" },
      include: { department: true, shift: true },
      orderBy: [{ department: { name: "asc" } }, { code: "asc" }, { id: "asc" }],
      take: ROSTER_EMPLOYEE_CAP,
    }),
    db.shift.findMany({ where: { companyId }, orderBy: { startTime: "asc" } }),
    db.shiftAssignment.findMany({
      where: { companyId, date: { gte: from, lte: to } },
      select: { employeeId: true, date: true, shiftId: true, isOff: true },
    }),
    db.department.findMany({
      where: { companyId }, select: { id: true, name: true }, orderBy: { name: "asc" },
    }),
    db.shiftSwapRequest.findMany({
      where: { companyId },
      include: { requester: { select: { firstName: true, lastName: true } }, peer: { select: { firstName: true, lastName: true } } },
      orderBy: { createdAt: "desc" },
      take: 30,
    }),
    db.employee.findMany({
      where: { companyId, status: "ACTIVE", ...(viewerEmployeeId ? { id: { not: viewerEmployeeId } } : {}) },
      select: { id: true, firstName: true, lastName: true, code: true, department: { select: { name: true } } },
      orderBy: { firstName: "asc" },
      take: 200,
    }),
    getPerms(viewerEmployeeId),
  ]);

  const byKey = new Map(assignments.map((a) => [`${a.employeeId}|${isoDate(a.date)}`, a]));
  const dayKeys = days.map(isoDate);
  const rosterEmployees: RosterEmployee[] = employees.map((e) => {
    const cells: Record<string, RosterCell> = {};
    for (const day of dayKeys) {
      const a = byKey.get(`${e.id}|${day}`);
      cells[day] = { shiftId: a?.shiftId ?? "", isOff: a?.isOff ?? false };
    }
    return {
      id: e.id,
      code: e.code,
      name: personName(e.firstName, e.lastName),
      dept: e.department?.name ?? "—",
      deptId: e.departmentId ?? "",
      defShift: e.shift?.name ?? null,
      defStart: e.shift?.startTime ?? null,
      cells,
    };
  });

  const swaps: RosterSwap[] = swapsRaw.map((s) => ({
    id: s.id,
    requester: personName(s.requester.firstName, s.requester.lastName),
    peer: personName(s.peer.firstName, s.peer.lastName),
    date: isoDate(s.date),
    note: s.note,
    status: s.status,
    mine: s.requesterId === viewerEmployeeId,
  }));

  return {
    ok: true as const,
    timeZone: ROSTER_TIME_ZONE,
    asOf: now.toISOString(),
    weekStart: isoDate(from),
    weekEnd: isoDate(to),
    prevW: isoDate(new Date(from.getTime() - 7 * DAY)),
    nextW: isoDate(new Date(from.getTime() + 7 * DAY)),
    today: isoDate(rosterDate(now)),
    days: dayKeys,
    departments,
    shifts: shifts.map((s): RosterShift => ({
      id: s.id, name: s.name, startTime: s.startTime, durationH: s.durationH,
    })),
    employees: rosterEmployees,
    swaps,
    peers: peers.map((p): RosterPeer => ({
      id: p.id,
      name: personName(p.firstName, p.lastName),
      code: p.code,
      department: p.department?.name ?? null,
    })),
    myEmployeeId: viewerEmployeeId,
    canSwap: Boolean(viewerEmployeeId) && perms.canSwapShift,
    pendingSwapCount: swaps.filter((s) => s.status === "PENDING").length,
  };
}

const entrySchema = z.object({
  employeeId: z.string().trim().min(1).max(128),
  date: z.string(),
  shiftId: z.union([z.string().trim().max(128), z.null()]).optional(),
  isOff: z.boolean(),
}).strict();

const saveSchema = z.object({
  entries: z.array(entrySchema).max(1000),
}).strict();

export type RosterSaveEntry = z.infer<typeof entrySchema>;

/** The same validated, tenant-scoped mutation powers web and mobile. */
export async function saveStaffRoster(companyId: string, input: unknown) {
  const parsed = saveSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false as const, status: 400, error: "Choose valid roster cells to save." };
  }
  const { entries } = parsed.data;
  if (entries.some((e) => !isIsoDate(e.date))) {
    return { ok: false as const, status: 400, error: "Choose valid roster cells to save." };
  }
  if (entries.length === 0) return { ok: true as const, saved: 0 };

  const [employees, shifts] = await Promise.all([
    db.employee.findMany({ where: { companyId }, select: { id: true } }),
    db.shift.findMany({ where: { companyId }, select: { id: true } }),
  ]);
  const empIds = new Set(employees.map((e) => e.id));
  const shiftIds = new Set(shifts.map((s) => s.id));

  for (const e of entries) {
    if (!empIds.has(e.employeeId)) {
      return { ok: false as const, status: 404, error: "Employee not found." };
    }
    const shiftId = e.isOff ? null : (e.shiftId ? e.shiftId : null);
    if (shiftId && !shiftIds.has(shiftId)) {
      return { ok: false as const, status: 400, error: "Unknown shift." };
    }
  }

  await db.$transaction(async (tx) => {
    for (const e of entries) {
      const date = toDateOnly(e.date);
      const shiftId = e.isOff ? null : (e.shiftId ? e.shiftId : null);
      if (!shiftId && !e.isOff) {
        await tx.shiftAssignment.deleteMany({ where: { employeeId: e.employeeId, date } });
        continue;
      }
      await tx.shiftAssignment.upsert({
        where: { employeeId_date: { employeeId: e.employeeId, date } },
        update: { shiftId, isOff: e.isOff },
        create: { companyId, employeeId: e.employeeId, date, shiftId, isOff: e.isOff },
      });
    }
  });

  return { ok: true as const, saved: entries.length };
}
