"use server";

import { revalidatePath } from "next/cache";
import { requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import { saveStaffRoster } from "@/lib/roster";
import type { ActionState } from "./auth";

/** Staff: bulk-save duty-roster cells (upsert per employee+date; empty entries get deleted). */
export async function saveRosterAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  let entries: unknown;
  try { entries = JSON.parse(String(formData.get("entries") ?? "[]")); } catch { return { error: await bt("Bad data.") }; }

  const result = await saveStaffRoster(me.companyId, { entries });
  if (!result.ok) return { error: await bt(result.error) };
  revalidatePath("/roster");
  return { success: (await bt("Roster saved for {n} cells ✔"))!.replace("{n}", String(result.saved)) };
}
