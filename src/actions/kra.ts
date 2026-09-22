"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff, requireUser } from "@/lib/auth";
import type { ActionState } from "./auth";

const EDITABLE = ["DRAFT", "OPEN"]; // staff can edit goals
const SELF_UPDATE = ["OPEN"]; // employees update own achieved

export async function createCycleAction(year: number, quarter: number): Promise<ActionState> {
  const me = await requireStaff();
  if (!(quarter >= 1 && quarter <= 4) || !(year >= 2020 && year <= 2100)) return { error: "Year/quarter ghalat hai." };
  const dup = await db.kraCycle.findFirst({ where: { companyId: me.companyId, year, quarter } });
  if (dup) return { error: `Q${quarter} ${year} da cycle pehlaan banea hai.` };
  await db.kraCycle.create({ data: { companyId: me.companyId, year, quarter } });
  revalidatePath("/kra/manage");
  return { success: "Cycle bana ditta — hun goals add karo." };
}

export async function addGoalAction(
  cycleId: string, employeeId: string, title: string, weight: number, target: number, unit: string
): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({ where: { id: cycleId, companyId: me.companyId } });
  if (!cycle) return { error: "Cycle nahi mila." };
  if (!EDITABLE.includes(cycle.status)) return { error: "Eh cycle lock ho chukka — goals edit nahi hou sakde." };
  if (!title.trim()) return { error: "Goal title zaroori hai." };
  if (!(weight >= 1 && weight <= 100)) return { error: "Weight 1-100 hona chahida." };
  if (!(target > 0)) return { error: "Target 0 ton vadda hove." };
  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  if (!emp) return { error: "Employee nahi mila." };
  await db.kraGoal.create({
    data: { cycleId, employeeId, title: title.trim(), weight, target, unit: unit.trim() || null },
  });
  revalidatePath("/kra/manage");
  return { success: "Goal add ho gya." };
}

export async function removeGoalAction(goalId: string): Promise<ActionState> {
  const me = await requireStaff();
  const goal = await db.kraGoal.findFirst({
    where: { id: goalId },
    include: { cycle: true },
  });
  if (!goal || goal.cycle.companyId !== me.companyId) return { error: "Goal nahi mila." };
  if (!EDITABLE.includes(goal.cycle.status)) return { error: "Cycle lock ho chukka." };
  await db.kraGoal.delete({ where: { id: goalId } });
  revalidatePath("/kra/manage");
  return { success: "Goal hata ditta." };
}

export async function publishCycleAction(cycleId: string): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({
    where: { id: cycleId, companyId: me.companyId },
    include: { goals: true },
  });
  if (!cycle) return { error: "Cycle nahi mila." };
  if (cycle.status !== "DRAFT") return { error: "Cycle pehlaan hi publish hai." };
  if (cycle.goals.length === 0) return { error: "Pehlaan goals add karo." };

  // Guard: every employee who has goals must total exactly 100% weight.
  const sums = new Map<string, number>();
  for (const g of cycle.goals) sums.set(g.employeeId, (sums.get(g.employeeId) ?? 0) + g.weight);
  const bad = [...sums.entries()].filter(([, s]) => s !== 100);
  if (bad.length > 0) {
    const names = await db.employee.findMany({ where: { id: { in: bad.map(([id]) => id) } }, select: { firstName: true, lastName: true } });
    return { error: `Weight total 100% hona zaroori: ${names.map((n) => `${n.firstName} ${n.lastName}`).join(", ")} da total ghalat hai.` };
  }

  await db.kraCycle.update({ where: { id: cycleId }, data: { status: "OPEN" } });
  revalidatePath("/kra/manage");
  revalidatePath("/kra");
  revalidatePath("/tops");
  return { success: "KRA publish ho gya — employees apni progress update kar sakde ne! 🎯" };
}

/** Employee self-update (OPEN) ya HR override (OPEN/SCORING). */
export async function updateAchievedAction(goalId: string, achieved: number): Promise<ActionState> {
  const me = await requireUser();
  const goal = await db.kraGoal.findFirst({
    where: { id: goalId },
    include: { cycle: true, employee: true },
  });
  if (!goal || goal.cycle.companyId !== me.companyId) return { error: "Goal nahi mila." };
  const staff = me.role !== "EMPLOYEE";
  const isSelf = me.employeeId === goal.employeeId;
  const allowed = (isSelf && SELF_UPDATE.includes(goal.cycle.status)) || (staff && (SELF_UPDATE.includes(goal.cycle.status) || goal.cycle.status === "SCORING"));
  if (!allowed) return { error: "Eh goal hun lock hai — sirf HR scoring vele edit hunda." };
  if (!(achieved >= 0)) return { error: "Value 0 ya vaddi hove." };
  await db.kraGoal.update({ where: { id: goalId }, data: { achieved } });
  revalidatePath("/kra");
  revalidatePath("/kra/manage");
  revalidatePath("/tops");
  return { success: "Progress update ✓" };
}

export async function startScoringAction(cycleId: string): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({ where: { id: cycleId, companyId: me.companyId } });
  if (!cycle) return { error: "Cycle nahi mila." };
  if (cycle.status !== "OPEN") return { error: "Sirf OPEN cycle scoring te ja sakda." };
  await db.kraCycle.update({ where: { id: cycleId }, data: { status: "SCORING" } });
  revalidatePath("/kra/manage");
  revalidatePath("/kra");
  return { success: "Scoring mode — employee edits band, HR review shuru. 📝" };
}

export async function closeCycleAction(cycleId: string): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({ where: { id: cycleId, companyId: me.companyId } });
  if (!cycle) return { error: "Cycle nahi mila." };
  if (cycle.status !== "SCORING") return { error: "Pehlaan 'Start scoring' karo." };
  await db.kraCycle.update({ where: { id: cycleId }, data: { status: "CLOSED", closedAt: new Date() } });
  revalidatePath("/kra/manage");
  revalidatePath("/kra");
  return { success: "Q close ho gya — scores lock. 🔒🏁" };
}
