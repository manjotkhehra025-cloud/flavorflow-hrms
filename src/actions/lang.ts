"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";

export async function setLanguageAction(lang: "en" | "pa"): Promise<void> {
  const me = await requireUser();
  await db.user.update({ where: { id: me.id }, data: { locale: lang } });
  revalidatePath("/", "layout");
}
