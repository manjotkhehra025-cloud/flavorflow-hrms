"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";

export async function addDepartmentAction(formData: FormData) {
  const me = await requireStaff();
  const name = (formData.get("name") as string)?.trim();
  if (!name) return;
  await db.department.upsert({
    where: { companyId_name: { companyId: me.companyId, name } },
    create: { companyId: me.companyId, name },
    update: {},
  });
  revalidatePath("/departments");
}

export async function deleteDepartmentAction(id: string) {
  const me = await requireStaff();
  if (me.role !== "ADMIN") return;
  await db.department.deleteMany({ where: { id, companyId: me.companyId } });
  revalidatePath("/departments");
}

export async function addDesignationAction(formData: FormData) {
  const me = await requireStaff();
  const title = (formData.get("title") as string)?.trim();
  if (!title) return;
  await db.designation.upsert({
    where: { companyId_title: { companyId: me.companyId, title } },
    create: { companyId: me.companyId, title },
    update: {},
  });
  revalidatePath("/departments");
}

export async function deleteDesignationAction(id: string) {
  const me = await requireStaff();
  if (me.role !== "ADMIN") return;
  await db.designation.deleteMany({ where: { id, companyId: me.companyId } });
  revalidatePath("/departments");
}
