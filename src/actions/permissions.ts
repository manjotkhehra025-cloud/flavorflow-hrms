"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { PERM_KEYS } from "./_perm-keys";
type PermKey = (typeof PERM_KEYS)[number];

/** Super admin: flip one permission toggle for an employee. */
export async function setEmployeePermissionAction(employeeId: string, key: string, allowed: boolean) {
  const me = await requireStaff();
  if (me.role !== "ADMIN") throw new Error("Super admin only.");
  if (!(PERM_KEYS as readonly string[]).includes(key)) throw new Error("Unknown permission key.");
  const k = key as PermKey;
  await db.employeePermission.upsert({
    where: { employeeId },
    create: { companyId: me.companyId, employeeId, [k]: allowed },
    update: { [k]: allowed },
  });
  revalidatePath(`/employees/${employeeId}`);
}
