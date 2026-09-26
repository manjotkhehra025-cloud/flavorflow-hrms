import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { db } from "@/lib/db";
import { kraScoreOf, kraGoalPct } from "@/lib/kra";

export const dynamic = "force-dynamic";

/** GET /api/kra — my KRA cycles + goals (mobile My KRA screen; same query + math as web /kra). */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (!me.employeeId) return NextResponse.json({ linked: false, cycles: [] });

  const goals = await db.kraGoal.findMany({
    where: { employeeId: me.employeeId, cycle: { companyId: me.companyId, status: { not: "DRAFT" } } },
    include: { cycle: true },
    orderBy: [{ cycle: { year: "desc" } }, { cycle: { quarter: "desc" } }, { createdAt: "asc" }],
  });

  const byCycle = new Map<string, { cycle: (typeof goals)[number]["cycle"]; goals: typeof goals }>();
  for (const g of goals) {
    const cur = byCycle.get(g.cycleId) ?? { cycle: g.cycle, goals: [] as typeof goals };
    cur.goals.push(g);
    byCycle.set(g.cycleId, cur);
  }

  const cycles = [...byCycle.values()].map(({ cycle, goals }) => ({
    id: cycle.id,
    year: cycle.year,
    quarter: cycle.quarter,
    status: cycle.status,
    score: kraScoreOf(goals),
    goals: goals.map((g) => ({
      id: g.id,
      title: g.title,
      weight: g.weight,
      target: g.target,
      achieved: g.achieved,
      unit: g.unit,
      pct: kraGoalPct(g.target, g.achieved),
    })),
  }));
  return NextResponse.json({ linked: true, staff: me.role !== "EMPLOYEE", cycles });
}

/** PATCH /api/kra {goalId, achieved} — self-update with the exact web rules (updateAchievedAction). */
const patchSchema = z.object({ goalId: z.string().min(1), achieved: z.number().min(0) });

export async function PATCH(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const parsed = patchSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return jsonError("Enter 0 or higher.", 400);
  const { goalId, achieved } = parsed.data;

  const goal = await db.kraGoal.findFirst({ where: { id: goalId }, include: { cycle: true } });
  if (!goal || goal.cycle.companyId !== me.companyId) return jsonError("Goal not found.", 404);
  const staff = me.role !== "EMPLOYEE";
  const isSelf = me.employeeId === goal.employeeId;
  const allowed =
    (isSelf && goal.cycle.status === "OPEN") ||
    (staff && (goal.cycle.status === "OPEN" || goal.cycle.status === "SCORING"));
  if (!allowed) return jsonError("This goal is locked — only HR can edit during scoring.", 403);

  await db.kraGoal.update({ where: { id: goalId }, data: { achieved } });
  return NextResponse.json({ ok: true });
}
