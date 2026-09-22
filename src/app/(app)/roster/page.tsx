import { Pa } from "@/components/Pa";

import { Suspense } from "react";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { PageHeader } from "@/components/ui";
import { RosterGrid } from "./RosterGrid";

export const dynamic = "force-dynamic";

const DAY = 24 * 60 * 60 * 1000;

function dstr(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** Monday of the week containing the given (UTC) date; avoid DST edge cases. */
function mondayOf(d: Date): Date {
  const dow = d.getUTCDay(); // 0..6
  const delta = (dow + 6) % 7; // Mon=0
  return new Date(d.getTime() - delta * DAY);
}

export default async function RosterPage({ searchParams }: { searchParams: Promise<{ w?: string }> }) {
  const me = await requireStaff();
  const sp = await searchParams;
  const anchor = sp.w ? new Date(sp.w + "T00:00:00.000Z") : new Date();
  const monday = mondayOf(anchor);
  const days = Array.from({ length: 7 }, (_, i) => new Date(monday.getTime() + i * DAY));
  const from = days[0], to = days[6];

  const [employees, shifts, assignments] = await Promise.all([
    db.employee.findMany({
      where: { companyId: me.companyId, status: "ACTIVE" },
      include: { department: true, shift: true },
      orderBy: [{ department: { name: "asc" } }, { code: "asc" }],
      take: 120,
    }),
    db.shift.findMany({ where: { companyId: me.companyId }, orderBy: { startTime: "asc" } }),
    db.shiftAssignment.findMany({ where: { companyId: me.companyId, date: { gte: from, lte: to } } }),
  ]);

  const grid: Record<string, { shiftId: string; isOff: boolean }> = {};
  for (const e of employees) for (const d of days) grid[e.id + "|" + dstr(d)] = { shiftId: "", isOff: false };
  for (const a of assignments) grid[a.employeeId + "|" + dstr(a.date)] = { shiftId: a.shiftId ?? "", isOff: a.isOff };

  const prevW = dstr(new Date(monday.getTime() - 7 * DAY));
  const nextW = dstr(new Date(monday.getTime() + 7 * DAY));

  return (
    <div className="space-y-5">
      <PageHeader
        title={<Pa>Duty roster 🗓️</Pa>}
        subtitle={<Pa>Assign weekly shifts & offs — payroll & late-mark rules use these automatically.</Pa>}
      />
      <Suspense fallback={null}>
        <RosterGrid
          employees={employees.map((e) => ({
            id: e.id, code: e.code, name: e.firstName + (e.lastName ? " " + e.lastName : ""),
            dept: e.department?.name ?? "—", defShift: e.shift?.name ?? null,
          }))}
          shifts={shifts.map((s) => ({ id: s.id, name: s.name, startTime: s.startTime }))}
          days={days.map(dstr)}
          grid={grid}
          prevW={prevW} nextW={nextW}
        />
      </Suspense>
    </div>
  );
}
