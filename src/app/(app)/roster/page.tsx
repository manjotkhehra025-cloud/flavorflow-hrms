import { Pa } from "@/components/Pa";

import { Suspense } from "react";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import { PageHeader } from "@/components/ui";
import { RosterGrid } from "./RosterGrid";
import { SwapPanel } from "@/components/SwapPanel";
import Link from "next/link";

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

export default async function RosterPage({ searchParams }: { searchParams: Promise<{ w?: string; tab?: string }> }) {
  const anyUser = await requireUser();
  if (anyUser.role === "EMPLOYEE") {
    const spE = await searchParams;
    return <RosterSwapsOnly companyId={anyUser.companyId} me={anyUser} week={(await searchParams).w} />;
  }
  const me = await requireStaff();
  const sp = await searchParams;
  const anchor = sp.w ? new Date(sp.w + "T00:00:00.000Z") : new Date();
  const monday = mondayOf(anchor);
  const days = Array.from({ length: 7 }, (_, i) => new Date(monday.getTime() + i * DAY));
  const from = days[0], to = days[6];

  const staffTab = sp.tab === "swaps" ? "swaps" : "grid";
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
      <div className="flex gap-1 rounded-2xl bg-slate-100 p-1 w-fit">
        <Link href="/roster" className={staffTab === "grid" ? "rounded-xl bg-white px-3.5 py-1.5 text-xs font-extrabold text-slate-800 shadow-sm" : "px-3.5 py-1.5 text-xs font-bold text-slate-500"}><Pa>Roster Grid</Pa></Link>
        <Link href="/roster?tab=swaps" className={staffTab === "swaps" ? "rounded-xl bg-white px-3.5 py-1.5 text-xs font-extrabold text-slate-800 shadow-sm" : "px-3.5 py-1.5 text-xs font-bold text-slate-500"}><Pa>Shift Swaps</Pa></Link>
      </div>
      {staffTab === "swaps" && <RosterSwapsOnly companyId={me.companyId} me={me} week={null} />}
      {staffTab === "grid" && <Suspense fallback={null}>
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
      </Suspense>}
    </div>
  );
}

/** Shared swaps view: staff get approval queue; employees get request form + history. */
async function RosterSwapsOnly({ companyId, me, week }: { companyId: string; me: { id: string; role: string; employeeId: string | null }; week?: string | null }) {
  const staff = me.role !== "EMPLOYEE";
  const [swaps, peers] = await Promise.all([
    db.shiftSwapRequest.findMany({
      where: { companyId, ...(staff ? {} : { OR: [{ requesterId: me.employeeId ?? "x" }, { peerId: me.employeeId ?? "x" }] }) },
      include: { requester: { include: { department: true } }, peer: true },
      orderBy: { createdAt: "desc" },
      take: 30,
    }),
    db.employee.findMany({ where: { companyId, status: "ACTIVE" }, include: { department: true }, orderBy: { firstName: "asc" } }),
  ]);
  const fmt = (d: Date) => new Date(d).toLocaleDateString("en-IN", { weekday: "short", day: "numeric", month: "short" });
  return (
    <SwapPanel
      staff={staff}
      myEmployeeId={me.employeeId}
      peers={peers.filter((p) => p.id !== me.employeeId).map((p) => ({ id: p.id, name: `${p.firstName} ${p.lastName ?? ""}`.trim() + " · " + (p.department?.name ?? "—") }))}
      swaps={swaps.map((w) => ({
        id: w.id,
        requester: `${w.requester.firstName} ${w.requester.lastName ?? ""}`.trim(),
        peer: `${w.peer.firstName} ${w.peer.lastName ?? ""}`.trim(),
        date: fmt(w.date),
        note: w.note,
        status: w.status,
        mine: w.requesterId === me.employeeId,
      }))}
    />
  );
}
