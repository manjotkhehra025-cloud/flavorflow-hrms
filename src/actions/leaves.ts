"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
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
  if (!me.employeeId) return { error: "Your account is not linked to an employee profile." };

  const parsed = leaveSchema.safeParse({
    leaveTypeId: formData.get("leaveTypeId"),
    fromDate: formData.get("fromDate"),
    toDate: formData.get("toDate"),
    reason: (formData.get("reason") as string)?.trim() || undefined,
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid data." };

  const from = toDateOnly(parsed.data.fromDate);
  const to = toDateOnly(parsed.data.toDate);
  if (to < from) return { error: "End date can't be before start date." };

  const days = dayDiffInclusive(from, to);
  if (days > 30) return { error: "Leave longer than 30 days needs admin entry." };

  const overlap = await db.leaveRequest.findFirst({
    where: {
      employeeId: me.employeeId,
      status: { in: ["PENDING", "APPROVED"] },
      fromDate: { lte: to },
      toDate: { gte: from },
    },
  });
  if (overlap) return { error: "You already have a leave request overlapping these dates." };

  await db.leaveRequest.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      leaveTypeId: parsed.data.leaveTypeId,
      fromDate: from,
      toDate: to,
      days,
      reason: parsed.data.reason,
    },
  });
  revalidatePath("/leaves");
  return {};
}

export async function decideLeaveAction(leaveId: string, decision: "APPROVED" | "REJECTED") {
  const me = await requireStaff();
  await db.leaveRequest.updateMany({
    where: { id: leaveId, companyId: me.companyId, status: "PENDING" },
    data: { status: decision, approverId: me.id, decidedAt: new Date() },
  });
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
