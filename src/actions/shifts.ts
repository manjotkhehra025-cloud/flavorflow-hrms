"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import type { ActionState } from "./auth";

const shiftSchema = z.object({
  name: z.string().min(2, "Shift name required"),
  startTime: z.string().min(4, "Start time required"),
  durationH: z.string().min(1, "Hours required"),
});

export async function createShiftAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const parsed = shiftSchema.safeParse({
    name: formData.get("name"),
    startTime: formData.get("startTime"),
    durationH: formData.get("durationH"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid data." };
  const d = parsed.data;
  const hours = parseFloat(d.durationH);
  if (!Number.isFinite(hours) || hours <= 0 || hours > 16) return { error: "Hours must be 0.5–16." };

  try {
    await db.shift.create({
      data: { companyId: me.companyId, name: d.name.trim(), startTime: d.startTime, durationH: hours },
    });
  } catch {
    return { error: "A shift with this name already exists." };
  }
  revalidatePath("/settings");
  revalidatePath("/employees");
  return { success: `Shift "${d.name}" created.` };
}

export async function deleteShiftAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const id = String(formData.get("id") ?? "");
  const shift = await db.shift.findFirst({ where: { id, companyId: me.companyId } });
  if (!shift) return { error: "Shift not found." };
  await db.employee.updateMany({ where: { shiftId: shift.id }, data: { shiftId: null } });
  await db.shift.delete({ where: { id: shift.id } });
  revalidatePath("/settings");
  revalidatePath("/employees");
  return { success: `Shift "${shift.name}" deleted.` };
}

/** One-tap: create G.D. Foods' 3 factory shifts if they don't exist yet. */
export async function seedFactoryShiftsAction(): Promise<ActionState> {
  const me = await requireStaff();
  const defaults = [
    { name: "General Day Shift", startTime: "08:00", durationH: 9 },
    { name: "Night Shift", startTime: "19:00", durationH: 12 },
    { name: "Season Day Shift", startTime: "07:00", durationH: 12 },
  ];
  for (const s of defaults) {
    await db.shift.upsert({
      where: { companyId_name: { companyId: me.companyId, name: s.name } },
      create: { companyId: me.companyId, ...s },
      update: { startTime: s.startTime, durationH: s.durationH },
    });
  }
  // Ensure the Earned Leave type exists with the 15-day yellow-card quota
  await db.leaveType.upsert({
    where: { companyId_name: { companyId: me.companyId, name: "Earned Leave" } },
    create: { companyId: me.companyId, name: "Earned Leave", daysPerYear: 15 },
    update: { daysPerYear: 15 },
  });
  revalidatePath("/settings");
  return { success: "Factory defaults ready: 3 shifts + Earned Leave (15/yr)." };
}
