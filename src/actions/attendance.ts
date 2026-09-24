"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate, distanceMeters } from "@/lib/utils";
import { permDenied } from "@/lib/permissions";

export type PunchInput = { selfiePath?: string; lat?: number; lng?: number; dist?: number };

export async function checkInAction(input?: FormData | string) {
  await checkInImpl(input as FormData | string);
}

/** Geo-secure variant for the client punch component — returns errors. */
export async function checkInGeoAction(input?: PunchInput) {
  return checkInImpl(input as PunchInput | undefined | null);
}

async function checkInImpl(input?: FormData | string | PunchInput | null) {
  const permMe = await requireUser();
  const denyIn = await permDenied(permMe.employeeId, "canPunch");
  if (denyIn) return { error: denyIn };
  const args: PunchInput = typeof input === "string"
    ? { selfiePath: input }
    : input instanceof FormData
      ? { selfiePath: (input.get("selfiePath") as string) || undefined }
      : (input ?? {});
  const me = await requireUser();
  if (!me.employeeId) return;
  const geoOut = await geofenceCheck(me.companyId, args);
  if (geoOut?.error) return geoOut;

  const existing = await db.attendance.findUnique({
    where: { employeeId_date: { employeeId: me.employeeId, date: todayDate() } },
  });
  if (existing?.checkIn) return;

  await db.attendance.upsert({
    where: { employeeId_date: { employeeId: me.employeeId, date: todayDate() } },
    create: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      date: todayDate(),
      checkIn: new Date(),
      status: "PRESENT",
      selfiePath: args.selfiePath?.startsWith("/api/selfie/") ? args.selfiePath : null,
      punchLat: args.lat ?? null,
      punchLng: args.lng ?? null,
      punchDist: args.dist ?? null,
    },
    update: { checkIn: new Date(), status: "PRESENT", selfiePath: args.selfiePath?.startsWith("/api/selfie/") ? args.selfiePath : undefined, punchLat: args.lat ?? undefined, punchLng: args.lng ?? undefined, punchDist: args.dist ?? undefined },
  });
  revalidatePath("/attendance");
  revalidatePath("/dashboard");
}

export async function checkOutAction(input?: FormData | string) {
  await checkOutImpl(input as FormData | string);
}

/** Geo-secure variant for the client punch component — returns errors. */
export async function checkOutGeoAction(input?: PunchInput) {
  return checkOutImpl(input as PunchInput | undefined | null);
}

async function checkOutImpl(input?: FormData | string | PunchInput | null) {
  const permMe = await requireUser();
  const denyOut = await permDenied(permMe.employeeId, "canPunch");
  if (denyOut) return { error: denyOut };
  const args: PunchInput = typeof input === "string"
    ? { selfiePath: input }
    : input instanceof FormData
      ? { selfiePath: (input.get("selfiePath") as string) || undefined }
      : (input ?? {});
  const me = await requireUser();
  if (!me.employeeId) return;
  const geoOut = await geofenceCheck(me.companyId, args);
  if (geoOut?.error) return geoOut;

  const existing = await db.attendance.findUnique({
    where: { employeeId_date: { employeeId: me.employeeId, date: todayDate() } },
  });
  if (!existing?.checkIn || existing.checkOut) return;

  const dataOut: { checkOut: Date; selfiePath?: string; punchLat?: number; punchLng?: number; punchDist?: number } = { checkOut: new Date() };
  if (args.selfiePath?.startsWith("/api/selfie/")) dataOut.selfiePath = args.selfiePath;
  if (args.lat != null) dataOut.punchLat = args.lat;
  if (args.lng != null) dataOut.punchLng = args.lng;
  if (args.dist != null) dataOut.punchDist = args.dist;
  await db.attendance.update({
    where: { id: existing.id },
    data: dataOut,
  });
  revalidatePath("/attendance");
  revalidatePath("/dashboard");
}

/** Server-side factory geofence enforcement (F2). */
async function geofenceCheck(companyId: string, args: { lat?: number; lng?: number }): Promise<{ error: string } | null> {
  const c = await db.company.findUnique({ where: { id: companyId }, select: { geofenceEnabled: true, geoLat: true, geoLng: true, geoRadius: true } });
  if (!c?.geofenceEnabled || c.geoLat == null || c.geoLng == null) return null;
  if (args.lat == null || args.lng == null) {
    return { error: "Punch needs GPS location — re-try from the punch screen." };
  }
  const dist = distanceMeters(args.lat, args.lng, c.geoLat, c.geoLng);
  if (dist > c.geoRadius) {
    return { error: `You are ${(dist / 1000).toFixed(2)} km from factory — punching allowed only within ${c.geoRadius} m of the gate.` };
  }
  return null;
}
