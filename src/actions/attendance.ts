"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { todayDate } from "@/lib/utils";

export async function checkInAction() {
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
    },
    update: { checkIn: new Date(), status: "PRESENT" },
  });
  revalidatePath("/attendance");
  revalidatePath("/dashboard");
}

export async function checkOutAction() {
  const me = await requireUser();
  if (!me.employeeId) return;

  const existing = await db.attendance.findUnique({
    where: { employeeId_date: { employeeId: me.employeeId, date: todayDate() } },
  });
  if (!existing?.checkIn || existing.checkOut) return;

  await db.attendance.update({
    where: { id: existing.id },
    data: { checkOut: new Date() },
  });
  revalidatePath("/attendance");
  revalidatePath("/dashboard");
}
