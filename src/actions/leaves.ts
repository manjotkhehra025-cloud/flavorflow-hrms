"use server";
import { bt } from "@/lib/i18n";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import { permDenied } from "@/lib/permissions";
import { canDecideFor } from "@/lib/approve-routing";
import { toDateOnly, dayDiffInclusive } from "@/lib/utils";
import type { ActionState } from "./auth";

const leaveSchema = z.object({
  leaveTypeId: z.string().min(1, "Choose a leave type"),
  fromDate: z.string().min(4, "From date is required"),
  toDate: z.string().min(4, "To date is required"),
  reason: z.string().optional(),
});

export async function applyLeaveAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  if (!me.employeeId) return { error: await bt("Your account is not linked to an employee profile.") };
  const leaveDeny = await permDenied(me.employeeId, "canApplyLeave");
  if (leaveDeny) return { error: await bt(leaveDeny) };

  const parsed = leaveSchema.safeParse({
    leaveTypeId: formData.get("leaveTypeId"),
    fromDate: formData.get("fromDate"),
    toDate: formData.get("toDate"),
    reason: (formData.get("reason") as string)?.trim() || undefined,
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid data." };

  const from = toDateOnly(parsed.data.fromDate);
  const to = toDateOnly(parsed.data.toDate);
  if (to < from) return { error: await bt("End date can't be before start date.") };

  const halfDay = formData.get("halfDay") === "on";
  if (halfDay && from.getTime() !== to.getTime()) return { error: await bt("Half-day leave is for a single day — set the same start & end date.") };

  const days = dayDiffInclusive(from, to);
  if (days > 30) return { error: await bt("Leave longer than 30 days needs admin entry.") };

  const overlap = await db.leaveRequest.findFirst({
    where: {
      employeeId: me.employeeId,
      status: { in: ["PENDING", "APPROVED"] },
      fromDate: { lte: to },
      toDate: { gte: from },
    },
  });
  if (overlap) return { error: await bt("You already have a leave request overlapping these dates.") };

  await db.leaveRequest.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      leaveTypeId: parsed.data.leaveTypeId,
      fromDate: from,
      toDate: to,
      days,
      halfDay,
      reason: parsed.data.reason,
    },
  });
  revalidatePath("/leaves");
  return {};
}

export async function decideLeaveAction(leaveId: string, decision: "APPROVED" | "REJECTED") {
  const me = await requireUser();
  const leave = await db.leaveRequest.findFirst({
    where: { id: leaveId, companyId: me.companyId, status: "PENDING" },
    include: { employee: { include: { department: { include: { parent: true } }, designation: true } } },
  });
  if (!leave) return;
  if (!(await canDecideFor(me, leave.employee as never))) throw new Error("Not your approval to take — this routes to the department head.");
  await db.leaveRequest.update({
    where: { id: leaveId },
    data: { status: decision, approverId: me.id, decidedAt: new Date() },
  });
  revalidatePath("/approvals");
  revalidatePath("/leaves");
  revalidatePath("/dashboard");
}

export async function cancelLeaveAction(leaveId: string) {
  const me = await requireUser();
  if (!me.employeeId) return;
  await db.leaveRequest.updateMany({
    where: { id: leaveId, employeeId: me.employeeId, status: "PENDING" },
    data: { status: "CANCELLED" },
  });
  revalidatePath("/leaves");
}
