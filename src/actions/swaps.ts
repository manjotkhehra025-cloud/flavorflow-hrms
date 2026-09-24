"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import { permDenied } from "@/lib/permissions";
import { canDecideFor } from "@/lib/approve-routing";
import { bt } from "@/lib/i18n";
import { toDateOnly } from "@/lib/utils";
import type { ActionState } from "./auth";

export async function createSwapRequestAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  if (!me.employeeId) return { error: await bt("Your login isn't linked to an employee profile.") };
  const swapDeny = await permDenied(me.employeeId, "canSwapShift");
  if (swapDeny) return { error: await bt(swapDeny) };
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
  return { success: await bt("Swap request sent") };
}

export async function decideSwapAction(id: string, approve: boolean) {
  const me = await requireUser();
  const req = await db.shiftSwapRequest.findFirst({
    where: { id, companyId: me.companyId, status: "PENDING" },
    include: { requester: { include: { department: { include: { parent: true } }, designation: true } } },
  });
  if (!req) return;
  if (!(await canDecideFor(me, req.requester as never))) throw new Error("Not your approval to take.");
  await db.shiftSwapRequest.update({
    where: { id },
    data: { status: approve ? "APPROVED" : "REJECTED", decidedAt: new Date() },
  });
  revalidatePath("/approvals");
}
