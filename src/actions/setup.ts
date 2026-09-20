"use server";

import { z } from "zod";
import bcrypt from "bcryptjs";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { seedOrgDefaults } from "@/lib/org";
import type { ActionState } from "./auth";

const setupSchema = z.object({
  companyName: z.string().min(2, "Company name is required"),
  companyCode: z
    .string()
    .min(2)
    .max(6)
    .regex(/^[A-Z0-9]+$/, "2–6 uppercase letters/numbers, e.g. FF"),
  name: z.string().min(2, "Your name is required"),
  email: z.string().email(),
  password: z.string().min(8, "Password must be at least 8 characters"),
});

/**
 * One-time bootstrap: only works while ZERO users exist in the database.
 * Creates the company, the owner (ADMIN) account and sensible org defaults.
 */
export async function setupAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const userCount = await db.user.count();
  if (userCount > 0) return { error: "Setup has already been completed. Please log in." };

  const parsed = setupSchema.safeParse({
    companyName: formData.get("companyName"),
    companyCode: (formData.get("companyCode") as string)?.toUpperCase().trim(),
    name: formData.get("name"),
    email: (formData.get("email") as string)?.toLowerCase().trim(),
    password: formData.get("password"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Invalid details." };
  }

  const { companyName, companyCode, name, email, password } = parsed.data;

  const company = await db.company.create({
    data: { name: companyName, code: companyCode },
  });

  await db.user.create({
    data: {
      companyId: company.id,
      name,
      email,
      role: "ADMIN",
      passwordHash: await bcrypt.hash(password, 10),
    },
  });

  await seedOrgDefaults(company.id);
  redirect("/login?setup=done");
}
