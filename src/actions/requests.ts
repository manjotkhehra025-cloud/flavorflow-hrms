"use server";
import { bt } from "@/lib/i18n";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import { todayDate, toDateOnly } from "@/lib/utils";
import type { ActionState } from "./auth";

// ---------- Gate Pass ----------

const gatePassSchema = z.object({
  date: z.string().min(4, "Date required"),
  exitAt: z.string().min(4, "Exit time required"),
  returnAt: z.string().optional(),
  reason: z.string().optional(),
});

export async function createGatePassAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();

  // Staff may create a pass on behalf of another employee
  const targetEmpId = (formData.get("employeeId") as string) || null;
  let employeeId = me.employeeId;
  if (targetEmpId && targetEmpId !== me.employeeId) {
    if (me.role === "EMPLOYEE") return { error: await bt("Not authorized.") };
    const target = await db.employee.findFirst({ where: { id: targetEmpId, companyId: me.companyId } });
    if (!target) return { error: await bt("Employee not found.") };
    employeeId = target.id;
  }
  if (!employeeId) return { error: await bt("Your login isn't linked to an employee profile.") };

  const parsed = gatePassSchema.safeParse({
    date: formData.get("date"),
    exitAt: formData.get("exitAt"),
    returnAt: formData.get("returnAt") || undefined,
    reason: formData.get("reason") || undefined,
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid data." };
  const d = parsed.data;

  await db.gatePass.create({
    data: {
      companyId: me.companyId,
      employeeId,
      date: toDateOnly(d.date),
      exitAt: d.exitAt,
      returnAt: d.returnAt || null,
      reason: d.reason || null,
    },
  });

  revalidatePath("/idcard");
  revalidatePath("/approvals");
  return { success: await bt("Gate pass requested. Manager will review it.") };
}

export async function decideGatePassAction(id: string, approve: boolean) {
  const me = await requireStaff();
  const pass = await db.gatePass.findFirst({ where: { id, companyId: me.companyId } });
  if (!pass || pass.status !== "PENDING") return;

  await db.gatePass.update({
    where: { id },
    data: {
      status: approve ? "APPROVED" : "REJECTED",
      approverId: me.id,
      decidedAt: new Date(),
    },
  });
  revalidatePath("/approvals");
  revalidatePath("/idcard");
}

export async function verifyGatePassAction(id: string) {
  const me = await requireStaff();
  const pass = await db.gatePass.findFirst({ where: { id, companyId: me.companyId } });
  if (!pass || pass.status !== "APPROVED" || pass.entryVerifiedAt) return;

  await db.gatePass.update({ where: { id }, data: { entryVerifiedAt: new Date() } });
  revalidatePath("/approvals");
  revalidatePath("/idcard");
}

// ---------- Manual Punch / OT ----------

const punchSchema = z.object({
  type: z.enum(["MANUAL_IN", "MANUAL_OUT", "OT"]),
  date: z.string().min(4, "Date required"),
  time: z.string().optional(),
  hours: z.string().optional(),
  reason: z.string().min(2, "Reason required"),
});

export async function createPunchRequestAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  if (!me.employeeId) return { error: await bt("Your login isn't linked to an employee profile.") };

  const parsed = punchSchema.safeParse({
    type: formData.get("type"),
    date: formData.get("date"),
    time: formData.get("time") || undefined,
    hours: formData.get("hours") || undefined,
    reason: formData.get("reason"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid data." };
  const d = parsed.data;

  if (d.type !== "OT" && !d.time) return { error: await bt("Time is required for manual punch.") };
  if (d.type === "OT") {
    const h = parseFloat(d.hours ?? "");
    if (!Number.isFinite(h) || h <= 0 || h > 12) return { error: await bt("OT hours must be 0.5–12.") };
  }

  await db.punchRequest.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      type: d.type,
      date: toDateOnly(d.date),
      time: d.type === "OT" ? null : (d.time ?? null),
      hours: d.type === "OT" ? parseFloat(d.hours!) : null,
      reason: d.reason.trim(),
    },
  });

  revalidatePath("/attendance");
  revalidatePath("/approvals");
  return { success: await bt("Request sent to manager for approval.") };
}

export async function decidePunchRequestAction(id: string, approve: boolean) {
  const me = await requireStaff();
  const req = await db.punchRequest.findFirst({ where: { id, companyId: me.companyId } });
  if (!req || req.status !== "PENDING") return;

  await db.punchRequest.update({
    where: { id },
    data: { status: approve ? "APPROVED" : "REJECTED", approverId: me.id, decidedAt: new Date() },
  });

  // Apply manual punch directly into Attendance when approved
  if (approve && req.type !== "OT" && req.time) {
    const stamp = new Date(`${req.date.toISOString().slice(0, 10)}T${req.time}:00+05:30`);
    const existing = await db.attendance.findUnique({
      where: { employeeId_date: { employeeId: req.employeeId, date: req.date } },
    });
    if (req.type === "MANUAL_IN") {
      if (!existing) {
        await db.attendance.create({
          data: {
            companyId: me.companyId,
            employeeId: req.employeeId,
            date: req.date,
            checkIn: stamp,
            status: "PRESENT",
            note: "Manual check-in approved",
          },
        });
      } else if (!existing.checkIn) {
        await db.attendance.update({ where: { id: existing.id }, data: { checkIn: stamp, note: "Manual check-in approved" } });
      }
    } else {
      // MANUAL_OUT
      if (!existing) {
        await db.attendance.create({
          data: {
            companyId: me.companyId,
            employeeId: req.employeeId,
            date: req.date,
            checkOut: stamp,
            status: "PRESENT",
            note: "Manual check-out approved",
          },
        });
      } else if (!existing.checkOut) {
        await db.attendance.update({ where: { id: existing.id }, data: { checkOut: stamp, note: "Manual check-out approved" } });
      }
    }
  }

  revalidatePath("/approvals");
  revalidatePath("/attendance");
}

// ---------- Leave balance adjustment ----------

export async function adjustLeaveBalanceAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const employeeId = formData.get("employeeId") as string;
  const leaveTypeId = formData.get("leaveTypeId") as string;
  const daysRaw = formData.get("days") as string;
  const note = (formData.get("note") as string) || null;

  if (!employeeId || !leaveTypeId) return { error: await bt("Employee and leave type required.") };
  const days = parseFloat(daysRaw);
  if (!Number.isFinite(days) || days === 0) return { error: await bt("Days must be a non-zero number (positive consumes, negative credits).") };

  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  if (!emp) return { error: await bt("Employee not found.") };

  await db.leaveAdjustment.create({
    data: {
      companyId: me.companyId,
      employeeId,
      leaveTypeId,
      days,
      note,
      createdBy: me.id,
    },
  });

  revalidatePath("/leaves");
  revalidatePath(`/employees/${employeeId}`);
  return { success: `Balance adjusted by ${days > 0 ? "-" : "+"}${Math.abs(days)} day(s).` };
}
