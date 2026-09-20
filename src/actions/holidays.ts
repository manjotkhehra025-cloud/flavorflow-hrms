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
  await db.holiday.upsert({
    where: { companyId_date: { companyId: me.companyId, date: toDateOnly(date) } },
    create: { companyId: me.companyId, name, date: toDateOnly(date) },
    update: { name },
  });
  revalidatePath("/holidays");
}

export async function deleteHolidayAction(id: string) {
  const me = await requireStaff();
  await db.holiday.deleteMany({ where: { id, companyId: me.companyId } });
  revalidatePath("/holidays");
}
