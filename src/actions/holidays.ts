"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { toDateOnly } from "@/lib/utils";

export async function addHolidayAction(formData: FormData) {
  const me = await requireStaff();
  const name = (formData.get("name") as string)?.trim();
  const date = formData.get("date") as string;
  if (!name || !date) return;
  const day = toDateOnly(date);
  await db.holiday.upsert({
    where: { companyId_date: { companyId: me.companyId, date: day } },
    create: { companyId: me.companyId, name, date: day },
    update: { name },
  });

  // Plant-closed / ad-hoc holiday ⇒ nobody is absent that day:
  // rows already marked ABSENT with no punch become HOLIDAY; rows with a punch stay as-is.
  await db.attendance.updateMany({
    where: { companyId: me.companyId, date: day, checkIn: null, status: "ABSENT" },
    data: { status: "HOLIDAY", note: name },
  });

  revalidatePath("/holidays");
  revalidatePath("/attendance");
  revalidatePath("/dashboard");
}

export async function deleteHolidayAction(id: string) {
  const me = await requireStaff();
  await db.holiday.deleteMany({ where: { id, companyId: me.companyId } });
  revalidatePath("/holidays");
}
