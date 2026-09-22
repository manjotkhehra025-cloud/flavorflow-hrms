import Link from "next/link";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Card, PageHeader, Badge, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";
import { kraScoreOf } from "@/lib/kra";
import { NewCycleForm } from "./NewCycleForm";
import { GoalEditor, type GoalDto } from "./GoalEditor";
import { publishCycleAction, startScoringAction, closeCycleAction } from "@/actions/kra";

export const dynamic = "force-dynamic";

const QTR_LABEL = ["", "Jan–Mar", "Apr–Jun", "Jul–Sep", "Oct–Dec"];
const TONE: Record<string, "green" | "amber" | "slate" | "blue"> = {
  DRAFT: "blue",
  OPEN: "green",
  SCORING: "amber",
  CLOSED: "slate",
};

export default async function KraManagePage({ searchParams }: { searchParams: Promise<{ cy?: string }> }) {
  const me = await requireStaff();
  const { cy } = await searchParams;

  const cycles = await db.kraCycle.findMany({
    where: { companyId: me.companyId },
    orderBy: [{ year: "desc" }, { quarter: "desc" }],
  });

  const cycle = cy ? cycles.find((c) => c.id === cy) : cycles[0];

  const [employees, goals] = cycle
    ? await Promise.all([
        db.employee.findMany({
          where: { companyId: me.companyId, status: "ACTIVE" },
          orderBy: { firstName: "asc" },
          select: { id: true, firstName: true, lastName: true, code: true },
        }),
        db.kraGoal.findMany({
          where: { cycleId: cycle.id },
          orderBy: { createdAt: "asc" },
        }),
      ])
    : [[], []];

  // group goals by employee
  const perEmp = new Map<string, GoalDto[]>();
  for (const g of goals as (typeof goals)[number][]) {
    const list = perEmp.get(g.employeeId) ?? [] as GoalDto[];
    list.push({ id: g.id, title: g.title, weight: g.weight, target: g.target, achieved: g.achieved, unit: g.unit });
    perEmp.set(g.employeeId, list);
  }
  const empIds = new Set([...employees.map((e) => e.id), ...perEmp.keys()]);
  const rows = employees.filter((e) => empIds.has(e.id));

  const invalid = [...perEmp.entries()]
    .filter(([, gs]) => gs.reduce((a, b) => a + b.weight, 0) !== 100)
    .map(([id]) => id);

  return (
    <div className="space-y-6">
      <PageHeader title="KRA Manage 🎯" subtitle="Quarterly weightage targets — set → publish → score → lock" />

      {/* Cycle picker */}
      <div className="flex flex-wrap items-center gap-2">
        {cycles.map((c) => (
          <Link
            key={c.id}
            href={`/kra/manage?cy=${c.id}`}
            className={`flex items-center gap-1.5 rounded-xl px-3.5 py-2 text-xs font-bold transition ${
              cycle?.id === c.id ? "bg-[#0a1628] text-white shadow-md" : "bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50"
            }`}
          >
            Q{c.quarter} {c.year}
            <Badge tone={TONE[c.status]}>{c.status}</Badge>
          </Link>
        ))}
        <NewCycleForm />
      </div>

      {!cycle ? (
        <Card className="p-5">
          <EmptyState icon="chart" title="No cycles yet" hint="Start with 'New cycle' above — add goals, then publish." />
        </Card>
      ) : (
        <>
          {/* Cycle header */}
          <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-6 text-white shadow-[var(--shadow-pop)]">
            <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-teal-500/15 blur-3xl" />
            <div className="relative flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-xs font-bold uppercase tracking-[0.2em] text-emerald-400/90">Cycle</p>
                <h2 className="mt-1 text-xl font-extrabold">Q{cycle.quarter} {cycle.year} <span className="text-sm font-medium text-slate-400">({QTR_LABEL[cycle.quarter]})</span></h2>
                <p className="mt-1 text-xs text-slate-400">
                  {goals.length} goals · {perEmp.size} employees · <Badge tone={TONE[cycle.status]}>{cycle.status}</Badge>
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                {cycle.status === "DRAFT" && (
                  <form
                    action={async () => {
                      "use server";
                      await publishCycleAction(cycle.id);
                    }}
                  >
                    <button className="flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-emerald-500 to-emerald-600 px-4 py-2.5 text-xs font-bold text-white shadow-[0_8px_20px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-95">
                      <Icon name="check" className="h-4 w-4" /> Publish cycle
                    </button>
                  </form>
                )}
                {cycle.status === "OPEN" && (
                  <form
                    action={async () => {
                      "use server";
                      await startScoringAction(cycle.id);
                    }}
                  >
                    <button className="flex items-center gap-1.5 rounded-xl bg-amber-500 px-4 py-2.5 text-xs font-bold text-white transition hover:bg-amber-600 active:scale-95">
                      📝 Start scoring
                    </button>
                  </form>
                )}
                {cycle.status === "SCORING" && (
                  <form
                    action={async () => {
                      "use server";
                      await closeCycleAction(cycle.id);
                    }}
                  >
                    <button className="flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-emerald-500 to-emerald-600 px-4 py-2.5 text-xs font-bold text-white transition hover:from-emerald-400 hover:to-emerald-500 active:scale-95">
                      🔒 Close & lock Q{cycle.quarter}
                    </button>
                  </form>
                )}
              </div>
            </div>
            {cycle.status === "DRAFT" && invalid.length > 0 && (
              <p className="relative mt-3 rounded-xl bg-amber-500/15 px-3.5 py-2 text-xs font-semibold text-amber-300 ring-1 ring-amber-400/20">
                ⚠ Before publishing: every employee weight must total exactly 100% — fix the {invalid.length} employee(s) shown in red.
              </p>
            )}
          </div>

          {/* Employee editors */}
          {rows.length === 0 && (
            <Card className="p-5">
              <EmptyState icon="users" title="Add goals first" hint="3–5 weightage goals per employee (total must be 100%)." />
            </Card>
          )}
          <div className="space-y-4">
            {rows.map((emp) => {
              const gs = perEmp.get(emp.id) ?? [];
              const score = kraScoreOf(gs);
              const wsum = gs.reduce((a, b) => a + b.weight, 0);
              return (
                <GoalEditor
                  key={emp.id}
                  cycleId={cycle.id}
                  cycleStatus={cycle.status}
                  employeeId={emp.id}
                  employeeName={`${emp.firstName} ${emp.lastName}`}
                  employeeCode={emp.code}
                  goals={gs}
                  scorePct={gs.length ? score.pct : null}
                  weightOk={wsum === 100}
                />
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
