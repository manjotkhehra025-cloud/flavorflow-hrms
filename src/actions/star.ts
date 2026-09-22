"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import type { ActionState } from "./auth";

export async function pickStarAction(employeeId: string, month: string, note: string): Promise<ActionState> {
  const me = await requireStaff();
  if (!/^\d{4}-\d{2}$/.test(month)) return { error: "Invalid month format (YYYY-MM)." };
  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId, status: "ACTIVE" } });
  if (!emp) return { error: "Employee not found." };
  const dup = await db.starAward.findFirst({ where: { companyId: me.companyId, month } });
  if (dup) {
    const who = await db.employee.findUnique({ where: { id: dup.employeeId }, select: { firstName: true, lastName: true } });
    return { error: `A star is already declared for this month: ${who?.firstName ?? ""} ${who?.lastName ?? ""}.` };
  }
  await db.starAward.create({
    data: {
      companyId: me.companyId,
      employeeId,
      month,
      note: note.trim() || null,
      createdBy: me.id,
    },
  });
  revalidatePath("/star");
  revalidatePath("/dashboard");
  return { success: `⭐ ${emp.firstName} ${emp.lastName} — Star of the Month declared!` };
}
