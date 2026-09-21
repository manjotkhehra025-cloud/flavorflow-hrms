"use server";

import { z } from "zod";
import bcrypt from "bcryptjs";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { setSessionCookie, clearSessionCookie, signSession } from "@/lib/auth";

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
