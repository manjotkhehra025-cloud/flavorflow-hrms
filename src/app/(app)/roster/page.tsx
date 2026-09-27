import { Pa } from "@/components/Pa";

import { Suspense } from "react";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import { PageHeader } from "@/components/ui";
import { RosterGrid } from "./RosterGrid";
import { SwapPanel } from "@/components/SwapPanel";
import { getStaffRoster } from "@/lib/roster";
import Link from "next/link";

export const dynamic = "force-dynamic";

export default async function RosterPage({ searchParams }: { searchParams: Promise<{ w?: string; tab?: string }> }) {
  const anyUser = await requireUser();
  if (anyUser.role === "EMPLOYEE") {
    return <RosterSwapsOnly companyId={anyUser.companyId} me={anyUser} week={(await searchParams).w} />;
  }
  const me = await requireStaff();
  const sp = await searchParams;
  const staffTab = sp.tab === "swaps" ? "swaps" : "grid";
  const snapshot = await getStaffRoster(me.companyId, { week: sp.w ?? null, viewerEmployeeId: me.employeeId });
  if (!snapshot.ok) {
    return (
      <div className="space-y-5">
        <PageHeader title={<Pa>Duty roster</Pa>} subtitle={<Pa>Invalid week.</Pa>} />
      </div>
    );
  }
  const grid: Record<string, { shiftId: string; isOff: boolean }> = {};
  for (const e of snapshot.employees) {
    for (const [day, cell] of Object.entries(e.cells)) grid[e.id + "|" + day] = cell;
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title={<Pa>Duty roster</Pa>}
        subtitle={<Pa>Assign weekly shifts & offs — payroll & late-mark rules use these automatically.</Pa>}
      />
      <div className="flex gap-1 rounded-2xl bg-slate-100 p-1 w-fit">
        <Link href="/roster" className={staffTab === "grid" ? "rounded-xl bg-white px-3.5 py-1.5 text-xs font-extrabold text-slate-800 shadow-sm" : "px-3.5 py-1.5 text-xs font-bold text-slate-500"}><Pa>Roster Grid</Pa></Link>
        <Link href="/roster?tab=swaps" className={staffTab === "swaps" ? "rounded-xl bg-white px-3.5 py-1.5 text-xs font-extrabold text-slate-800 shadow-sm" : "px-3.5 py-1.5 text-xs font-bold text-slate-500"}><Pa>Shift Swaps</Pa></Link>
      </div>
      {staffTab === "swaps" && <RosterSwapsOnly companyId={me.companyId} me={me} week={null} />}
      {staffTab === "grid" && <Suspense fallback={null}>
        <RosterGrid
          employees={snapshot.employees.map((e) => ({
            id: e.id, code: e.code, name: e.name, dept: e.dept, defShift: e.defShift,
          }))}
          shifts={snapshot.shifts.map((s) => ({ id: s.id, name: s.name, startTime: s.startTime }))}
          days={snapshot.days}
          grid={grid}
          prevW={snapshot.prevW} nextW={snapshot.nextW}
          today={snapshot.today}
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
