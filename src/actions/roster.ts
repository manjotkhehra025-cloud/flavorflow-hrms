"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import type { ActionState } from "./auth";

type Entry = { employeeId: string; date: string; shiftId: string | null; isOff: boolean };

/** Staff: bulk-save duty-roster cells (upsert per employee+date; empty entries get deleted). */
export async function saveRosterAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  let entries: Entry[];
  try { entries = JSON.parse(String(formData.get("entries") ?? "[]")); } catch { return { error: await bt("Bad data.") }; }

  const empIds = new Set((await db.employee.findMany({ where: { companyId: me.companyId }, select: { id: true } })).map((e) => e.id));
  const shifts = new Set((await db.shift.findMany({ where: { companyId: me.companyId }, select: { id: true } })).map((s) => s.id));

  for (const e of entries) {
    if (!empIds.has(e.employeeId)) continue;
    const date = new Date(e.date + "T00:00:00.000Z");
    if (Number.isNaN(date.getTime())) continue;
    const shiftId = e.shiftId && shifts.has(e.shiftId) ? e.shiftId : null;
    if (!shiftId && !e.isOff) {
      await db.shiftAssignment.deleteMany({ where: { employeeId: e.employeeId, date } });
      continue;
    }
    await db.shiftAssignment.upsert({
      where: { employeeId_date: { employeeId: e.employeeId, date } },
      update: { shiftId, isOff: e.isOff },
      create: { companyId: me.companyId, employeeId: e.employeeId, date, shiftId, isOff: e.isOff },
    });
  }
  revalidatePath("/roster");
  return { success: (await bt("Roster saved for {n} cells ✔"))!.replace("{n}", String(entries.length)) };
}
