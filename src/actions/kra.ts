"use server";
import { bt } from "@/lib/i18n";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff, requireUser } from "@/lib/auth";
import type { ActionState } from "./auth";

const EDITABLE = ["DRAFT", "OPEN"]; // staff can edit goals
const SELF_UPDATE = ["OPEN"]; // employees update own achieved

export async function createCycleAction(year: number, quarter: number): Promise<ActionState> {
  const me = await requireStaff();
  if (!(quarter >= 1 && quarter <= 4) || !(year >= 2020 && year <= 2100)) return { error: await bt("Invalid year/quarter.") };
  const dup = await db.kraCycle.findFirst({ where: { companyId: me.companyId, year, quarter } });
  if (dup) return { error: `Q${quarter} ${year}  already has a cycle.` };
  await db.kraCycle.create({ data: { companyId: me.companyId, year, quarter } });
  revalidatePath("/kra/manage");
  return { success: await bt("Cycle created — now add goals.") };
}

export async function addGoalAction(
  cycleId: string, employeeId: string, title: string, weight: number, target: number, unit: string
): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({ where: { id: cycleId, companyId: me.companyId } });
  if (!cycle) return { error: await bt("Cycle not found.") };
  if (!EDITABLE.includes(cycle.status)) return { error: await bt("This cycle is locked — goals can no longer be edited.") };
  if (!title.trim()) return { error: await bt("Goal title is required.") };
  if (!(weight >= 1 && weight <= 100)) return { error: await bt("Weight must be between 1 and 100.") };
  if (!(target > 0)) return { error: await bt("Target must be greater than 0.") };
  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  if (!emp) return { error: await bt("Employee not found.") };
  await db.kraGoal.create({
    data: { cycleId, employeeId, title: title.trim(), weight, target, unit: unit.trim() || null },
  });
  revalidatePath("/kra/manage");
  return { success: await bt("Goal added.") };
}

export async function removeGoalAction(goalId: string): Promise<ActionState> {
  const me = await requireStaff();
  const goal = await db.kraGoal.findFirst({
    where: { id: goalId },
    include: { cycle: true },
  });
  if (!goal || goal.cycle.companyId !== me.companyId) return { error: await bt("Goal not found.") };
  if (!EDITABLE.includes(goal.cycle.status)) return { error: await bt("This cycle is locked.") };
  await db.kraGoal.delete({ where: { id: goalId } });
  revalidatePath("/kra/manage");
  return { success: await bt("Goal removed.") };
}

export async function publishCycleAction(cycleId: string): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({
    where: { id: cycleId, companyId: me.companyId },
    include: { goals: true },
  });
  if (!cycle) return { error: await bt("Cycle not found.") };
  if (cycle.status !== "DRAFT") return { error: await bt("This cycle is already published.") };
  if (cycle.goals.length === 0) return { error: await bt("Add some goals first.") };

  // Guard: every employee who has goals must total exactly 100% weight.
  const sums = new Map<string, number>();
  for (const g of cycle.goals) sums.set(g.employeeId, (sums.get(g.employeeId) ?? 0) + g.weight);
  const bad = [...sums.entries()].filter(([, s]) => s !== 100);
  if (bad.length > 0) {
    const names = await db.employee.findMany({ where: { id: { in: bad.map(([id]) => id) } }, select: { firstName: true, lastName: true } });
    return { error: `Each employee weight must total exactly 100% — fix these: ${names.map((n) => `${n.firstName} ${n.lastName}`).join(", ")} have an incorrect total.` };
  }

  await db.kraCycle.update({ where: { id: cycleId }, data: { status: "OPEN" } });
  revalidatePath("/kra/manage");
  revalidatePath("/kra");
  revalidatePath("/tops");
  return { success: await bt("KRA published — employees can now update their progress! 🎯") };
}

/** Employee self-update (OPEN) ya HR override (OPEN/SCORING). */
export async function updateAchievedAction(goalId: string, achieved: number): Promise<ActionState> {
  const me = await requireUser();
  const goal = await db.kraGoal.findFirst({
    where: { id: goalId },
    include: { cycle: true, employee: true },
  });
  if (!goal || goal.cycle.companyId !== me.companyId) return { error: await bt("Goal not found.") };
  const staff = me.role !== "EMPLOYEE";
  const isSelf = me.employeeId === goal.employeeId;
  const allowed = (isSelf && SELF_UPDATE.includes(goal.cycle.status)) || (staff && (SELF_UPDATE.includes(goal.cycle.status) || goal.cycle.status === "SCORING"));
  if (!allowed) return { error: await bt("This goal is locked — only HR can edit during scoring.") };
  if (!(achieved >= 0)) return { error: await bt("Enter 0 or higher.") };
  await db.kraGoal.update({ where: { id: goalId }, data: { achieved } });
  revalidatePath("/kra");
  revalidatePath("/kra/manage");
  revalidatePath("/tops");
  return { success: await bt("Progress update ✓") };
}

export async function startScoringAction(cycleId: string): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({ where: { id: cycleId, companyId: me.companyId } });
  if (!cycle) return { error: await bt("Cycle not found.") };
  if (cycle.status !== "OPEN") return { error: await bt("Only an OPEN cycle can move to scoring.") };
  await db.kraCycle.update({ where: { id: cycleId }, data: { status: "SCORING" } });
  revalidatePath("/kra/manage");
  revalidatePath("/kra");
  return { success: await bt("Scoring mode on — employee edits are frozen. HR review time! 📝") };
}

export async function closeCycleAction(cycleId: string): Promise<ActionState> {
  const me = await requireStaff();
  const cycle = await db.kraCycle.findFirst({ where: { id: cycleId, companyId: me.companyId } });
  if (!cycle) return { error: await bt("Cycle not found.") };
  if (cycle.status !== "SCORING") return { error: await bt("Use 'Start scoring' first.") };
  await db.kraCycle.update({ where: { id: cycleId }, data: { status: "CLOSED", closedAt: new Date() } });
  revalidatePath("/kra/manage");
  revalidatePath("/kra");
  return { success: await bt("Quarter closed — scores are locked. 🔒🏁") };
}
