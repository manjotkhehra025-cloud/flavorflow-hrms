"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import type { ActionState } from "./auth";

function toInt(v: unknown, fb: number): number {
  const n = parseInt(String(v ?? ""), 10);
  return Number.isFinite(n) && n >= 0 && n <= 60 ? n : fb;
}

/** Staff: pay rules (E3 paid leave for daily earners, E4 late-mark LOP rule). */
export async function savePayRulesAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const dailyPaidLeaveDays = toInt(formData.get("dailyPaidLeaveDays"), 0);
  const lateGraceMins = toInt(formData.get("lateGraceMins"), 15);
  const latesPerCut = toInt(formData.get("latesPerCut"), 0);
  await db.company.update({
    where: { id: me.companyId },
    data: { dailyPaidLeaveDays, lateGraceMins, latesPerCut },
  });
  revalidatePath("/settings");
  return { success: await bt("Pay rules saved ✔") };
}
