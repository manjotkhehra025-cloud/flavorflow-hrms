"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate } from "@/lib/utils";

export async function checkInAction(input?: FormData | string) {
  const selfiePath = typeof input === "string"
    ? input
    : input instanceof FormData
      ? ((input.get("selfiePath") as string) || undefined)
      : undefined;
  const me = await requireUser();
  if (!me.employeeId) return;

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
      selfiePath: selfiePath?.startsWith("/api/selfie/") ? selfiePath : null,
    },
    update: { checkIn: new Date(), status: "PRESENT", selfiePath: selfiePath?.startsWith("/api/selfie/") ? selfiePath : undefined },
  });
  revalidatePath("/attendance");
  revalidatePath("/dashboard");
}

export async function checkOutAction(input?: FormData | string) {
  const selfiePath = typeof input === "string"
    ? input
    : input instanceof FormData
      ? ((input.get("selfiePath") as string) || undefined)
      : undefined;
  const me = await requireUser();
  if (!me.employeeId) return;

  const existing = await db.attendance.findUnique({
    where: { employeeId_date: { employeeId: me.employeeId, date: todayDate() } },
  });
  if (!existing?.checkIn || existing.checkOut) return;

  const dataOut: { checkOut: Date; selfiePath?: string } = { checkOut: new Date() };
  if (selfiePath?.startsWith("/api/selfie/")) dataOut.selfiePath = selfiePath;
  await db.attendance.update({
    where: { id: existing.id },
    data: dataOut,
  });
  revalidatePath("/attendance");
  revalidatePath("/dashboard");
}
