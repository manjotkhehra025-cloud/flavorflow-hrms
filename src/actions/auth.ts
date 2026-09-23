"use server";

import { z } from "zod";
import bcrypt from "bcryptjs";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { bt } from "@/lib/i18n";
import { setSessionCookie, clearSessionCookie, signSession, requireUser } from "@/lib/auth";

const loginSchema = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string().min(1),
});

export type ActionState = { error?: string; success?: string };

export async function loginAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = loginSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });
  if (!parsed.success) return { error: "Enter a valid email and password." };

  const user = await db.user.findUnique({
    where: { email: parsed.data.email },
    include: { company: true },
  });

  if (!user || !user.isActive) return { error: "Invalid credentials." };
  const ok = await bcrypt.compare(parsed.data.password, user.passwordHash);
  if (!ok) return { error: "Invalid credentials." };

  const token = await signSession({
    id: user.id,
    companyId: user.companyId,
    companyName: user.company.name,
    email: user.email,
    name: user.name,
    role: user.role,
    employeeId: user.employeeId,
  });
  await setSessionCookie(token);
  redirect("/dashboard");
}

export async function logoutAction() {
  await clearSessionCookie();
  redirect("/login");
}

/** Signed-in: change own password (needs current password). */
export async function changePasswordAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const current = String(formData.get("current") ?? "");
  const next = String(formData.get("next") ?? "");
  if (next.length < 6) return { error: await bt("New PIN/password must be at least 6 characters.") };
  const user = await db.user.findUnique({ where: { id: me.id } });
  if (!user || !(await bcrypt.compare(current, user.passwordHash))) return { error: await bt("Current password is wrong.") };
  await db.user.update({ where: { id: me.id }, data: { passwordHash: await bcrypt.hash(next, 10) } });
  return { success: await bt("Password changed ✔ — use it from next login.") };
}

/** Admin/HR: reset an employee's login to a temporary password (shown once). */
export async function adminResetPasswordAction(formData: FormData): Promise<{ temp?: string; error?: string }> {
  const me = await requireUser();
  if (me.role === "EMPLOYEE") return { error: await bt("Not authorized.") };
  const userId = String(formData.get("userId") ?? "");
  const target = await db.user.findFirst({ where: { id: userId, companyId: me.companyId } });
  if (!target) return { error: await bt("User not found.") };
  const temp = "GDF" + Math.random().toString(36).slice(2, 8).toUpperCase();
  await db.user.update({ where: { id: target.id }, data: { passwordHash: await bcrypt.hash(temp, 10) } });
  return { temp };
}
