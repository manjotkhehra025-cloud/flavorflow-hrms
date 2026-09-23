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
    data: { dailyPaidLeaveDays, lateGraceMins, latesPerCut, punchSelfieRequired: formData.get("punchSelfieRequired") === "on" },
  });
  revalidatePath("/settings");
  return { success: await bt("Pay rules saved ✔") };
}

/** Staff: factory geofence for punches (F2). */
export async function saveGeofenceAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const enabled = formData.get("geofenceEnabled") === "on";
  const lat = parseFloat(String(formData.get("geoLat") ?? ""));
  const lng = parseFloat(String(formData.get("geoLng") ?? ""));
  const radius = parseFloat(String(formData.get("geoRadius") ?? "200"));
  if (enabled && (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180)) {
    return { error: await bt("Set factory GPS location first (use the 📍 my-location button).") };
  }
  await db.company.update({
    where: { id: me.companyId },
    data: {
      geofenceEnabled: enabled,
      geoLat: Number.isFinite(lat) ? lat : null,
      geoLng: Number.isFinite(lng) ? lng : null,
      geoRadius: Number.isFinite(radius) && radius >= 25 && radius <= 5000 ? radius : 200,
    },
  });
  revalidatePath("/settings");
  revalidatePath("/dashboard");
  return { success: await bt("Geofence saved ✔ — punches outside the radius will be blocked.") };
}
