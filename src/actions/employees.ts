"use server";
import { bt } from "@/lib/i18n";

import { z } from "zod";
import bcrypt from "bcryptjs";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { nextEmployeeCode } from "@/lib/org";
import { toDateOnly } from "@/lib/utils";
import type { ActionState } from "./auth";

const employeeSchema = z.object({
  firstName: z.string().min(1, "First name is required"),
  lastName: z.string().min(1, "Last name is required"),
  email: z.string().email().optional().or(z.literal("")),
  phone: z.string().optional(),
  gender: z.string().optional(),
  joinDate: z.string().min(4, "Join date is required"),
  departmentId: z.string().optional(),
  designationId: z.string().optional(),
  address: z.string().optional(),
  dateOfBirth: z.string().optional(),
  category: z.enum(["OFFICIAL", "YELLOW_CARD"]).default("OFFICIAL"),
  weeklyOff: z.coerce.number().int().min(0).max(6).default(0),
  shiftId: z.string().optional(),
  bloodGroup: z.string().optional(),
  emergencyPhone: z.string().optional(),
  createAccount: z.boolean().default(false),
  accountRole: z.enum(["HR", "EMPLOYEE"]).default("EMPLOYEE"),
  tempPassword: z.string().optional(),
});

function emptyToUndefined(v: string | undefined) {
  return v && v.length > 0 ? v : undefined;
}

export async function createEmployeeAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();

  const parsed = employeeSchema.safeParse({
    firstName: formData.get("firstName"),
    lastName: formData.get("lastName"),
    email: (formData.get("email") as string)?.trim(),
    phone: formData.get("phone") ?? undefined,
    gender: formData.get("gender") ?? undefined,
    joinDate: formData.get("joinDate"),
    departmentId: formData.get("departmentId") ?? undefined,
    designationId: formData.get("designationId") ?? undefined,
    address: formData.get("address") ?? undefined,
    dateOfBirth: formData.get("dateOfBirth") || undefined,
    category: formData.get("category") === "YELLOW_CARD" ? "YELLOW_CARD" : "OFFICIAL",
    weeklyOff: formData.get("weeklyOff") ?? 0,
    shiftId: formData.get("shiftId") ?? undefined,
    bloodGroup: formData.get("bloodGroup") ?? undefined,
    emergencyPhone: formData.get("emergencyPhone") ?? undefined,
    createAccount: formData.get("createAccount") === "on",
    accountRole: formData.get("accountRole") === "HR" ? "HR" : "EMPLOYEE",
    tempPassword: formData.get("tempPassword") ?? undefined,
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid data." };
  const d = parsed.data;

  if (d.createAccount) {
    if (!d.email) return { error: await bt("Email is required to create a login account.") };
    if (!d.tempPassword || d.tempPassword.length < 8)
      return { error: await bt("Temporary password must be at least 8 characters.") };
  }

  // Friendly guard instead of a DB unique-violation crash: email already owns a login?
  if (d.createAccount && d.email) {
    const taken = await db.user.findUnique({ where: { email: d.email.toLowerCase() } });
    if (taken)
      return {
        error:
          "This email is already linked to a login account. If it is your OWN account: untick the checkbox, save the employee, then link your login from the dashboard 'Link your login' card (punch works right away).",
      };
  }

  const company = await db.company.findUniqueOrThrow({ where: { id: me.companyId } });
  const code = await nextEmployeeCode(me.companyId, company.code);

  // Single transaction: employee + login either both save or neither (no half-saved rows).
  let employee;
  try {
    employee = await db.$transaction(async (tx) => {
      const emp = await tx.employee.create({
        data: {
          companyId: me.companyId,
          code,
          firstName: d.firstName.trim(),
          lastName: d.lastName.trim(),
          email: emptyToUndefined(d.email?.toLowerCase()),
          phone: emptyToUndefined(d.phone?.trim()),
          gender: emptyToUndefined(d.gender),
          joinDate: toDateOnly(d.joinDate),
          departmentId: emptyToUndefined(d.departmentId) ?? null,
          designationId: emptyToUndefined(d.designationId) ?? null,
          address: emptyToUndefined(d.address?.trim()),
          dateOfBirth: d.dateOfBirth ? toDateOnly(d.dateOfBirth) : null,
          category: d.category,
          weeklyOff: d.weeklyOff,
          shiftId: emptyToUndefined(d.shiftId) ?? null,
          bloodGroup: emptyToUndefined(d.bloodGroup?.trim()),
          emergencyPhone: emptyToUndefined(d.emergencyPhone?.trim()),
          status: "ACTIVE",
        },
      });

      if (d.createAccount && d.email && d.tempPassword) {
        await tx.user.create({
          data: {
            companyId: me.companyId,
            email: d.email.toLowerCase(),
            name: `${d.firstName} ${d.lastName}`,
            role: d.accountRole,
            passwordHash: await bcrypt.hash(d.tempPassword, 10),
            employeeId: emp.id,
          },
        });
      }
      return emp;
    });
  } catch (e) {
    console.error("createEmployeeAction failed:", e);
    return { error: await bt("Could not save employee — duplicate email or invalid data. Check the fields and try again.") };
  }

  revalidatePath("/employees");
  redirect(`/employees/${employee.id}`);
}

/** Staff edit of profile basics (category, shift, weekly-off, emergency info). */
export async function updateEmployeeDetailsAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const id = formData.get("employeeId") as string;
  if (!id) return { error: await bt("Employee missing.") };

  const weeklyOff = parseInt((formData.get("weeklyOff") as string) ?? "0", 10);
  const data = {
    category: formData.get("category") === "YELLOW_CARD" ? ("YELLOW_CARD" as const) : ("OFFICIAL" as const),
    weeklyOff: Number.isFinite(weeklyOff) && weeklyOff >= 0 && weeklyOff <= 6 ? weeklyOff : 0,
    shiftId: emptyToUndefined((formData.get("shiftId") as string) ?? "") ?? null,
    bloodGroup: emptyToUndefined(((formData.get("bloodGroup") as string) ?? "").trim()),
    emergencyPhone: emptyToUndefined(((formData.get("emergencyPhone") as string) ?? "").trim()),
    phone: emptyToUndefined(((formData.get("phone") as string) ?? "").trim()),
    dateOfBirth: formData.get("dateOfBirth") ? toDateOnly(formData.get("dateOfBirth") as string) : null,
    contractor: emptyToUndefined(((formData.get("contractor") as string) ?? "").trim()),
  };

  const res = await db.employee.updateMany({ where: { id, companyId: me.companyId }, data });
  if (res.count === 0) return { error: await bt("Employee not found.") };
  revalidatePath(`/employees/${id}`);
  revalidatePath("/employees");
  return { success: await bt("Profile updated.") };
}

export async function updateEmployeeStatusAction(employeeId: string, status: "ACTIVE" | "INACTIVE") {
  const me = await requireStaff();
  await db.employee.updateMany({
    where: { id: employeeId, companyId: me.companyId },
    data: { status },
  });
  if (status === "INACTIVE") {
    await db.user.updateMany({ where: { employeeId }, data: { isActive: false } });
  }
  revalidatePath("/employees");
  revalidatePath(`/employees/${employeeId}`);
}

export async function deleteEmployeeAction(employeeId: string) {
  const me = await requireStaff();
  if (me.role !== "ADMIN") return;
  await db.user.deleteMany({ where: { employeeId, companyId: me.companyId } });
  await db.employee.deleteMany({ where: { id: employeeId, companyId: me.companyId } });
  revalidatePath("/employees");
  redirect("/employees");
}

/** Staff: change one employee's weekly-off day (inline, fire-and-forget). */
export async function setWeeklyOffAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const id = String(formData.get("employeeId") ?? "");
  const weeklyOff = parseInt(String(formData.get("weeklyOff") ?? "0"), 10);
  const res = await db.employee.updateMany({
    where: { id, companyId: me.companyId },
    data: { weeklyOff: Number.isFinite(weeklyOff) && weeklyOff >= 0 && weeklyOff <= 6 ? weeklyOff : 0 },
  });
  if (res.count === 0) return { error: await bt("Employee not found.") };
  revalidatePath("/team");
  return { success: await bt("Weekly off updated ✔") };
}
