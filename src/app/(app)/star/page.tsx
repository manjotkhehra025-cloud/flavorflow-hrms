import Link from "next/link";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Card, PageHeader, Badge, EmptyState } from "@/components/ui";
import { AvatarImg } from "@/components/AvatarImg";
import { kraScoreOf } from "@/lib/kra";
import { pickStarAction } from "@/actions/star";
import { todayDate } from "@/lib/utils";

export const dynamic = "force-dynamic";

function monthKey(d: Date) {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}
function monthLabel(key: string) {
  const [y, m] = key.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString("en-IN", { month: "long", year: "numeric" });
}

export default async function StarPage({ searchParams }: { searchParams: Promise<{ m?: string }> }) {
  const me = await requireStaff();
  const { m } = await searchParams;
  const key = /^\d{4}-\d{2}$/.test(m ?? "") ? m! : monthKey(new Date());

  const [y, mo] = key.split("-").map(Number);
  const monthStart = new Date(Date.UTC(y, mo - 1, 1));
  const monthEnd = new Date(Date.UTC(y, mo, 1));

  const [employees, awards, attendance, tickets, kraGoals] = await Promise.all([
    db.employee.findMany({ where: { companyId: me.companyId, status: "ACTIVE" }, orderBy: { firstName: "asc" } }),
    db.starAward.findMany({
      where: { companyId: me.companyId },
      include: { employee: true },
      orderBy: { month: "desc" },
      take: 12,
    }),
    db.attendance.findMany({
      where: { companyId: me.companyId, date: { gte: monthStart, lt: monthEnd }, checkIn: { not: null } },
      select: { employeeId: true },
    }),
    db.ticket.findMany({
      where: { companyId: me.companyId, createdAt: { gte: monthStart, lt: monthEnd } },
      select: { employeeId: true },
    }),
    db.kraGoal.findMany({
      where: { cycle: { companyId: me.companyId, status: { in: ["OPEN", "SCORING", "CLOSED"] } } },
      select: { employeeId: true, weight: true, target: true, achieved: true, cycleId: true },
    }),
  ]);

  const picked = awards.find((a) => a.month === key);

  const presentByEmp = new Map<string, number>();
  for (const a of attendance) presentByEmp.set(a.employeeId, (presentByEmp.get(a.employeeId) ?? 0) + 1);
  const ticketsByEmp = new Map<string, number>();
  for (const t of tickets) ticketsByEmp.set(t.employeeId, (ticketsByEmp.get(t.employeeId) ?? 0) + 1);
  const kraByEmp = new Map<string, { weight: number; target: number; achieved: number }[]>();
  for (const g of kraGoals) {
    const list = kraByEmp.get(g.employeeId) ?? [];
    list.push({ weight: g.weight, target: g.target, achieved: g.achieved });
    kraByEmp.set(g.employeeId, list);
  }

  const candidates = employees
    .map((e) => {
      const present = presentByEmp.get(e.id) ?? 0;
      const kra = kraByEmp.has(e.id) ? kraScoreOf(kraByEmp.get(e.id)!).pct : 0;
      const complaints = ticketsByEmp.get(e.id) ?? 0;
      return { e, present, kra, complaints, score: present * 4 + kra / 5 - complaints };
    })
    .sort((a, b) => b.score - a.score);

  return (
    <div className="space-y-6">
      <PageHeader title="⭐ Star of the Month" subtitle="Auto-shortlist (attendance + KRA) — the final pick is yours" />

      {/* Month picker */}
      <div className="flex flex-wrap items-center gap-2">
        {Array.from({ length: 4 }, (_, i) => {
          const d = new Date();
          d.setUTCMonth(d.getUTCMonth() - i);
          const k = monthKey(d);
          return (
            <Link
              key={k}
              href={`/star?m=${k}`}
              className={`rounded-xl px-3.5 py-2 text-xs font-bold transition ${k === key ? "bg-[#0a1628] text-white" : "bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50"}`}
            >
              {monthLabel(k)}
            </Link>
          );
        })}
      </div>

      {picked && (
        <Card className="border-l-4! border-l-amber-400! p-5">
          <p className="text-xs font-bold uppercase tracking-wide text-amber-600">⭐ Star already declared for {monthLabel(key)}</p>
          <p className="mt-1.5 text-sm font-extrabold text-slate-900">
            {picked.employee.firstName} {picked.employee.lastName}
            {picked.note && <span className="ml-2 text-xs font-medium text-slate-500">· {picked.note}</span>}
          </p>
        </Card>
      )}

      {/* Shortlist */}
      {!picked && (
        <Card className="p-5">
          <h3 className="text-sm font-bold text-slate-900">Auto shortlist — {monthLabel(key)}</h3>
          <p className="mb-4 text-xs text-slate-400">Attendance (×4) + KRA score — complaints. Tap Pick ⭐ — add a note if you like.</p>
          <ul className="divide-y divide-slate-100">
            {candidates.slice(0, 6).map((c, i) => (
              <li key={c.e.id} className="flex flex-wrap items-center gap-3 py-3">
                <span className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-extrabold ${i === 0 ? "bg-amber-400 text-amber-950" : i === 1 ? "bg-slate-300 text-slate-700" : i === 2 ? "bg-orange-300 text-orange-900" : "bg-slate-100 text-slate-400"}`}>
                  {i + 1}
                </span>
                <AvatarImg name={`${c.e.firstName} ${c.e.lastName}`} photoUrl={c.e.photoUrl} size="h-9 w-9" textSize="text-[11px]" />
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-semibold text-slate-800">{c.e.firstName} {c.e.lastName}</div>
                  <div className="flex flex-wrap gap-1.5 text-[10px] font-semibold">
                    <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-emerald-700">🟢 {c.present} present</span>
                    {c.kra > 0 && <span className="rounded-full bg-sky-50 px-2 py-0.5 text-sky-700">🎯 KRA {c.kra}%</span>}
                    {c.complaints > 0 && <span className="rounded-full bg-rose-50 px-2 py-0.5 text-rose-600">💬 {c.complaints}</span>}
                  </div>
                </div>
                <form
                  action={async (fd: FormData) => {
                    "use server";
                    await pickStarAction(c.e.id, key, (fd.get("note") as string) ?? "");
                  }}
                  className="flex items-center gap-1.5"
                >
                  <input
                    name="note"
                    placeholder="Note (optional)"
                    className="w-28 rounded-lg border border-slate-200 px-2.5 py-2 text-[11px] outline-none focus:border-emerald-400 sm:w-40"
                  />
                  <button className="rounded-xl bg-gradient-to-r from-amber-400 to-amber-500 px-3.5 py-2 text-xs font-extrabold text-amber-950 shadow-sm transition hover:from-amber-300 hover:to-amber-400 active:scale-95">
                    ⭐ Pick
                  </button>
                </form>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {/* Hall of fame */}
      <Card className="p-5">
        <h3 className="mb-4 text-sm font-bold text-slate-900">Hall of Fame 🏆</h3>
        {awards.length === 0 ? (
          <EmptyState icon="badge" title="No stars yet" hint="Declare the first star — it will shine on everyone's dashboard!" />
        ) : (
          <div className="flex gap-3 overflow-x-auto pb-2">
            {awards.map((a) => (
              <div key={a.id} className="relative w-32 shrink-0 overflow-hidden rounded-2xl bg-[#0a1628] p-3.5 text-center text-white">
                <div className="pointer-events-none absolute -right-8 -top-8 h-20 w-20 rounded-full bg-amber-400/25 blur-2xl" />
                <div className="relative">
                  <div className="mx-auto">
                    <AvatarImg name={`${a.employee.firstName} ${a.employee.lastName}`} photoUrl={a.employee.photoUrl} size="h-12 w-12" textSize="text-sm" />
                  </div>
                  <p className="mt-2 text-xs font-extrabold leading-tight">{a.employee.firstName} {a.employee.lastName}</p>
                  <p className="mt-0.5 text-[10px] font-semibold text-amber-300">{monthLabel(a.month)}</p>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
