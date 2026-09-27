import Link from "next/link";
import { requireStaff } from "@/lib/auth";
import { Tt } from "@/components/LangCtx";
import { shortDate } from "@/lib/utils";
import { getTeamSnapshot, TEAM_DAY_NAMES } from "@/lib/team";
import { TeamBoard } from "@/components/TeamBoard";

export const dynamic = "force-dynamic";

export default async function TeamPage({ searchParams }: { searchParams: Promise<{ dept?: string; tab?: string }> }) {
  const me = await requireStaff();
  const sp = await searchParams;
  const tab = sp.tab === "leaves" ? "leaves" : "board";
  const { rows, counts, departments, leaves } = await getTeamSnapshot(me.companyId, sp.dept ?? "");
  const leaveRows = leaves.map((l) => ({ ...l, from: shortDate(l.fromDate), to: shortDate(l.toDate) }));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight text-slate-900"><Tt>Live Team</Tt></h1>
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
          departments={departments}
          activeDept={sp.dept ?? ""}
          dayNames={TEAM_DAY_NAMES}
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
              {leaveRows.length === 0 && <tr><td colSpan={4} className="px-4 py-10 text-center text-sm text-slate-400"><Tt>No approved leaves in the next 14 days</Tt></td></tr>}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
