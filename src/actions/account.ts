"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff, signSession, setSessionCookie } from "@/lib/auth";

export type LinkState = { ok?: boolean; error?: string };

/**
 * Let an ADMIN/HR user bind their login to an Employee profile (one-time setup,
 * so they can punch in/out and appear on the boards).
 */
export async function linkSelfToEmployeeAction(employeeId: string): Promise<LinkState> {
  const me = await requireStaff();
  if (me.employeeId) return { error: "Your account is already linked." };

  const emp = await db.employee.findFirst({
    where: { id: employeeId, companyId: me.companyId, status: "ACTIVE" },
  });
  if (!emp) return { error: "Employee profile not found." };

  const alreadyLinked = await db.user.findFirst({ where: { employeeId: emp.id } });
  if (alreadyLinked) return { error: `"${emp.firstName} ${emp.lastName}" already has a login linked.` };

  await db.user.update({ where: { id: me.id }, data: { employeeId: emp.id } });

  // Session cookie carries employeeId in its claims — re-sign so the change is live immediately.
  const token = await signSession({ ...me, employeeId: emp.id });
  await setSessionCookie(token);

  revalidatePath("/", "layout");
  return { ok: true };
}
