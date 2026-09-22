import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { Card, PageHeader, Badge, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";
import { kraScoreOf, kraGoalPct } from "@/lib/kra";
import { KraSelfUpdate } from "./KraSelfUpdate";

export const dynamic = "force-dynamic";

const TONE: Record<string, "green" | "amber" | "slate" | "blue"> = {
  OPEN: "green",
  SCORING: "amber",
  CLOSED: "slate",
  DRAFT: "blue",
};
const QTR_LABEL = ["", "Jan–Mar", "Apr–Jun", "Jul–Sep", "Oct–Dec"];

export default async function MyKraPage() {
  const me = await requireUser();

  if (!me.employeeId) {
    return (
      <div>
        <PageHeader title="My KRA 🎯" subtitle="Quarterly targets & auto-score" />
        <Card className="p-5">
          <EmptyState icon="chart" title="Account link nahi hai" hint="Apna login employee profile naal link karo — dashboard de 'Link account' card ton. Fer KRA es thaan dikhega." />
        </Card>
      </div>
    );
  }

  const goals = await db.kraGoal.findMany({
    where: { employeeId: me.employeeId, cycle: { companyId: me.companyId, status: { not: "DRAFT" } } },
    include: { cycle: true },
    orderBy: [{ cycle: { year: "desc" } }, { cycle: { quarter: "desc" } }, { createdAt: "asc" }],
  });

  // group by cycle
  const byCycle = new Map<string, { cycle: (typeof goals)[number]["cycle"]; goals: typeof goals }>();
  for (const g of goals) {
    const cur = byCycle.get(g.cycleId) ?? { cycle: g.cycle, goals: [] as typeof goals };
    cur.goals.push(g);
    byCycle.set(g.cycleId, cur);
  }
  const cycles = [...byCycle.values()];
  const active = cycles.find((c) => c.cycle.status === "OPEN" || c.cycle.status === "SCORING");
  const history = cycles.filter((c) => c.cycle.status === "CLOSED");

  return (
    <div className="space-y-6">
      <PageHeader
        title="My KRA 🎯"
        subtitle="Quarter de weightage targets — HR publish kare, tu update karein, score auto bane"
      />

      {cycles.length === 0 && (
        <Card className="p-5">
          <EmptyState icon="chart" title="KRA hale set nahi hoya" hint="HR quarter cycle publish karegi te tuhade goals es thaan dikhan ge 🎯" />
        </Card>
      )}

      {active && <KraView bucket={active} canEdit={active.cycle.status === "OPEN"} />}

      {history.length > 0 && (
        <Card className="p-5">
          <h3 className="mb-3 text-sm font-bold text-slate-900">Past quarters 🏁</h3>
          <ul className="divide-y divide-slate-100">
            {history.map(({ cycle, goals }) => {
              const s = kraScoreOf(goals);
              return (
                <li key={cycle.id} className="flex items-center justify-between py-2.5">
                  <div>
                    <span className="text-sm font-semibold text-slate-800">
                      Q{cycle.quarter} {cycle.year} <span className="text-xs font-normal text-slate-400">({QTR_LABEL[cycle.quarter]})</span>
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={`text-sm font-extrabold ${s.pct >= 75 ? "text-emerald-600" : s.pct >= 50 ? "text-amber-600" : "text-rose-500"}`}>
                      {s.pct}%
                    </span>
                    <Badge tone={s.pct >= 75 ? "green" : s.pct >= 50 ? "amber" : "red"}>{s.pct >= 75 ? "Excellent" : s.pct >= 50 ? "Good" : "Needs work"}</Badge>
                  </div>
                </li>
              );
            })}
          </ul>
        </Card>
      )}

      {me.role !== "EMPLOYEE" && (
        <p className="text-center text-xs text-slate-400">
          HR/Admin? <Link href="/kra/manage" className="font-semibold text-emerald-600 hover:underline">KRA manage karo →</Link>
        </p>
      )}
    </div>
  );
}

function KraView({ bucket, canEdit }: { bucket: { cycle: { year: number; quarter: number; status: string }; goals: { id: string; title: string; weight: number; target: number; achieved: number; unit: string | null }[] }; canEdit: boolean }) {
  const { cycle, goals } = bucket;
  const s = kraScoreOf(goals);
  const deg = Math.round((s.pct / 100) * 360);

  return (
    <>
      <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-6 text-white shadow-[var(--shadow-pop)]">
        <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-emerald-500/20 blur-3xl" />
        <div className="relative text-center">
          <div className="flex items-center justify-center gap-2">
            <span className="text-xs font-bold uppercase tracking-[0.2em] text-emerald-400/90">
              Q{cycle.quarter} {cycle.year} · {QTR_LABEL[cycle.quarter]}
            </span>
            <Badge tone={TONE[cycle.status]}>{cycle.status === "SCORING" ? "HR SCORING" : cycle.status}</Badge>
          </div>
          <div
            className="mx-auto mt-4 flex h-28 w-28 items-center justify-center rounded-full"
            style={{ background: `conic-gradient(#10b981 0 ${deg}deg, rgb(255 255 255 / 0.08) ${deg}deg 360deg)` }}
          >
            <div className="flex h-[5.4rem] w-[5.4rem] flex-col items-center justify-center rounded-full bg-[#0a1628]">
              <span className="text-2xl font-extrabold text-emerald-400">{s.pct}%</span>
              <span className="text-[9px] font-semibold uppercase tracking-wider text-slate-500">auto score</span>
            </div>
          </div>
          <p className="mt-3 text-xs text-slate-400">
            {cycle.status === "OPEN" && "Apni progress update karo — quarter end te HR final score karegi"}
            {cycle.status === "SCORING" && "⏳ HR review chal rahi — edits filhaal band ne"}
          </p>
        </div>
      </div>

      <Card className="space-y-3 p-4">
        {goals.map((g) => {
          const pct = kraGoalPct(g.target, g.achieved);
          return (
            <div key={g.id} className="rounded-2xl border border-slate-100 bg-white p-4">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <h4 className="text-sm font-bold text-slate-800">{g.title}</h4>
                  <p className="mt-0.5 text-xs text-slate-500">
                    Target: <b className="text-slate-700">{g.target}</b> {g.unit ?? ""} · Achieved: <b className="text-emerald-600">{g.achieved}</b> {g.unit ?? ""}
                  </p>
                </div>
                <span className="shrink-0 rounded-full bg-emerald-50 px-2.5 py-1 text-[10px] font-extrabold text-emerald-700 ring-1 ring-emerald-200">
                  {g.weight}% WT
                </span>
              </div>
              <div className="mt-3 h-2 overflow-hidden rounded-full bg-slate-100">
                <div
                  className={`h-full rounded-full transition-all ${pct >= 75 ? "bg-gradient-to-r from-emerald-500 to-emerald-400" : pct >= 50 ? "bg-gradient-to-r from-amber-500 to-amber-400" : "bg-gradient-to-r from-rose-400 to-rose-300"}`}
                  style={{ width: `${Math.max(3, pct)}%` }}
                />
              </div>
              <div className="mt-1.5 flex items-center justify-between text-[11px] font-semibold">
                <span className="text-slate-400">{pct}% complete</span>
                <span className="text-slate-500">{Math.round(((Math.min(100, pct) * g.weight) / 100) * 10) / 10}/{g.weight} pts</span>
              </div>
              {canEdit && <KraSelfUpdate goalId={g.id} achieved={g.achieved} unit={g.unit} />}
            </div>
          );
        })}
      </Card>
    </>
  );
}
