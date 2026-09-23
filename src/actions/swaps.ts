"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import { toDateOnly } from "@/lib/utils";
import type { ActionState } from "./auth";

export async function createSwapRequestAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  if (!me.employeeId) return { error: await bt("Your login isn't linked to an employee profile.") };
  const peerId = String(formData.get("peerId") ?? "");
  const date = String(formData.get("date") ?? "");
  const note = (String(formData.get("note") ?? "").trim() || null);
  if (!peerId || !date) return { error: await bt("Teammate and date required.") };
  if (peerId === me.employeeId) return { error: await bt("You can't swap with yourself!") };
  const peer = await db.employee.findFirst({ where: { id: peerId, companyId: me.companyId, status: "ACTIVE" } });
  if (!peer) return { error: await bt("Teammate not found.") };
  const dup = await db.shiftSwapRequest.findFirst({ where: { companyId: me.companyId, requesterId: me.employeeId, date: toDateOnly(date), status: "PENDING" } });
  if (dup) return { error: await bt("You already have a pending swap for this date.") };
  await db.shiftSwapRequest.create({ data: { companyId: me.companyId, requesterId: me.employeeId, peerId, date: toDateOnly(date), note } });
  revalidatePath("/roster");
  revalidatePath("/approvals");
  return { success: await bt("Swap request sent 🔁") };
}

export async function decideSwapAction(id: string, approve: boolean) {
  const me = await requireStaff();
  const req = await db.shiftSwapRequest.findFirst({ where: { id, companyId: me.companyId, status: "PENDING" } });
  if (!req) return;

  if (approve) {
    await db.$transaction(async (tx) => {
      const [a, b] = await Promise.all([
        tx.shiftAssignment.findFirst({ where: { companyId: req.companyId, employeeId: req.requesterId, date: req.date } }),
        tx.shiftAssignment.findFirst({ where: { companyId: req.companyId, employeeId: req.peerId, date: req.date } }),
      ]);
      const [empA, empB] = await Promise.all([
        tx.employee.findUnique({ where: { id: req.requesterId } }),
        tx.employee.findUnique({ where: { id: req.peerId } }),
      ]);
      const shiftA = a?.shiftId ?? empA?.shiftId ?? null;
      const shiftB = b?.shiftId ?? empB?.shiftId ?? null;
      const offA = a?.isOff ?? false;
      const offB = b?.isOff ?? false;
      if (a) await tx.shiftAssignment.update({ where: { id: a.id }, data: { shiftId: shiftB, isOff: offB } });
      else await tx.shiftAssignment.upsert({ where: { employeeId_date: { employeeId: req.requesterId, date: req.date } }, update: { shiftId: shiftB, isOff: offB }, create: { companyId: req.companyId, employeeId: req.requesterId, date: req.date, shiftId: shiftB, isOff: offB } });
      if (b) await tx.shiftAssignment.update({ where: { id: b.id }, data: { shiftId: shiftA, isOff: offA } });
      else await tx.shiftAssignment.upsert({ where: { employeeId_date: { employeeId: req.peerId, date: req.date } }, update: { shiftId: shiftA, isOff: offA }, create: { companyId: req.companyId, employeeId: req.peerId, date: req.date, shiftId: shiftA, isOff: offA } });
      await tx.shiftSwapRequest.update({ where: { id: req.id }, data: { status: "APPROVED", approverId: me.id, decidedAt: new Date() } });
    });
  } else {
    await db.shiftSwapRequest.update({ where: { id: req.id }, data: { status: "REJECTED", approverId: me.id, decidedAt: new Date() } });
  }
  revalidatePath("/roster");
  revalidatePath("/approvals");
}
