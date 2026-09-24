"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import bcrypt from "bcryptjs";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { bt } from "@/lib/i18n";
import { setSessionCookie, clearSessionCookie, signSession, requireUser } from "@/lib/auth";

const loginSchema = z.object({
  email: z.string().trim().email().toLowerCase(),
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
  let ok = await bcrypt.compare(parsed.data.password, user.passwordHash);
  if (!ok && parsed.data.password !== parsed.data.password.trim()) {
    // Mobile keyboards/autofill often surround passwords with spaces — retry trimmed.
    ok = await bcrypt.compare(parsed.data.password.trim(), user.passwordHash);
  }
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

/** Super admin: reset an employee's login — admin TYPES a starting password (never displayed back); employee must replace it at first login. */
export async function adminResetPasswordAction(formData: FormData): Promise<{ ok?: boolean; error?: string }> {
  const me = await requireUser();
  if (me.role !== "ADMIN") return { error: await bt("Super admin only.") };
  const userId = String(formData.get("userId") ?? "");
  const starting = String(formData.get("newPassword") ?? "").trim();
  if (starting.length < 6) return { error: await bt("Starting password must be at least 6 characters.") };
  const target = await db.user.findFirst({ where: { id: userId, companyId: me.companyId } });
  if (!target) return { error: await bt("User not found.") };
  await db.user.update({
    where: { id: target.id },
    data: { passwordHash: await bcrypt.hash(starting, 10), mustChangePassword: true },
  });
  revalidatePath("/employees");
  return { ok: true };
}

/** First-login flow: employee picks THEIR OWN password — then we sign them out so they log in fresh. */
export async function setInitialPasswordAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const p1 = String(formData.get("newPassword") ?? "").trim();
  const p2 = String(formData.get("confirmPassword") ?? "").trim();
  if (p1.length < 6) return { error: await bt("Your new password must be at least 6 characters.") };
  if (p1 !== p2) return { error: await bt("Both passwords don't match — type them again.") };
  const user = await db.user.findUnique({ where: { id: me.id } });
  if (!user) return { error: await bt("Account not found.") };
  if (await bcrypt.compare(p1, user.passwordHash)) return { error: await bt("New password can't be the starting one — pick something only you know.") };
  await db.user.update({
    where: { id: me.id },
    data: { passwordHash: await bcrypt.hash(p1, 10), mustChangePassword: false },
  });
  // Sign them out: they must log in again with the new password before the dashboard.
  await clearSessionCookie();
  redirect("/login?changed=1");
}
