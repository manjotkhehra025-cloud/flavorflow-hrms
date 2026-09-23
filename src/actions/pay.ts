"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import type { ActionState } from "./auth";

function toInt(v: unknown): number | null {
  const n = parseInt(String(v ?? "").replace(/[^\d]/g, ""), 10);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

/** Staff: set an employee's salary model, rates & bank details. */
export async function updateSalaryAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const employeeId = String(formData.get("employeeId") ?? "");
  if (!employeeId) return { error: await bt("Employee missing.") };

  const salaryType = formData.get("salaryType") === "DAILY" ? "DAILY" : "MONTHLY";
  const baseSalary = toInt(formData.get("baseSalary"));
  const dailyRate = toInt(formData.get("dailyRate"));
  const otRate = toInt(formData.get("otRate")); // null → auto at payroll time
  const bankAccount = (String(formData.get("bankAccount") ?? "").replace(/[^\d]/g, "") || null);
  const ifsc = (String(formData.get("ifsc") ?? "").trim().toUpperCase() || null);
  const pfEnabled = formData.get("pfEnabled") === "on";
  const pfNumber = (String(formData.get("pfNumber") ?? "").trim().toUpperCase() || null);
  const esiEnabled = formData.get("esiEnabled") === "on";
  const esiNumber = (String(formData.get("esiNumber") ?? "").trim() || null);

  if (salaryType === "MONTHLY" && (!baseSalary || baseSalary <= 0)) {
    return { error: await bt("Monthly base salary is required (₹/month).") };
  }
  if (salaryType === "DAILY" && (!dailyRate || dailyRate <= 0)) {
    return { error: await bt("Daily rate is required (₹/day).") };
  }
  if (bankAccount && (bankAccount.length < 9 || bankAccount.length > 18)) {
    return { error: await bt("Bank account number looks wrong (9–18 digits).") };
  }
  if (ifsc && !/^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc)) {
    return { error: await bt("IFSC looks wrong (e.g. SBIN0123456).") };
  }

  const before = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  const res = await db.employee.updateMany({
    where: { id: employeeId, companyId: me.companyId },
    data: { salaryType, baseSalary: baseSalary ?? null, dailyRate: dailyRate ?? null, otRate: otRate ?? null, bankAccount, ifsc,
            pfEnabled, pfNumber: pfEnabled ? pfNumber : null, esiEnabled, esiNumber: esiEnabled ? esiNumber : null },
  });
  // Phase E2: pay-audit trail (only when numbers/model actually change)
  if (before && (before.salaryType !== salaryType || (before.baseSalary ?? null) !== (baseSalary ?? null) || (before.dailyRate ?? null) !== (dailyRate ?? null))) {
    const oldAmt = before.salaryType === "DAILY" ? before.dailyRate : before.baseSalary;
    const newAmt = salaryType === "DAILY" ? dailyRate : baseSalary;
    let changeType = "REVISION";
    if (oldAmt == null && newAmt != null) changeType = "CREATE";
    else if (before.salaryType !== salaryType) changeType = "MODEL_SWITCH";
    else if ((newAmt ?? 0) > (oldAmt ?? 0)) changeType = "RAISE";
    else if ((newAmt ?? 0) < (oldAmt ?? 0)) changeType = "DEMOTE";
    await db.salaryRevision.create({
      data: {
        employeeId: before.id, companyId: me.companyId,
        effectiveDate: new Date(),
        changeType,
        oldSalaryType: before.salaryType, newSalaryType: salaryType,
        oldSalary: oldAmt ?? null, newSalary: newAmt ?? null,
        createdById: me.id,
      },
    });
  }
  if (res.count === 0) return { error: await bt("Employee not found.") };
  revalidatePath(`/employees/${employeeId}`);
  return { success: await bt("Salary setup saved 💾") };
}

/** Staff: record an advance given to an employee. */
export async function addAdvanceAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const employeeId = String(formData.get("employeeId") ?? "");
  const amount = toInt(formData.get("amount"));
  if (!employeeId) return { error: await bt("Employee missing.") };
  if (!amount || amount <= 0) return { error: await bt("Advance amount must be ₹1 or more.") };
  if (amount > 500000) return { error: await bt("Advance amount looks too high — double-check.") };

  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  if (!emp) return { error: await bt("Employee not found.") };

  const dRaw = String(formData.get("givenDate") ?? "").trim();
  const givenDate = dRaw ? new Date(dRaw + "T00:00:00.000Z") : new Date();
  const reason = (String(formData.get("reason") ?? "").trim() || null);
  const emiRaw = toInt(formData.get("emi"));
  const emi = emiRaw && emiRaw > 0 ? Math.min(emiRaw, amount) : null;

  await db.advance.create({
    data: { companyId: me.companyId, employeeId, amount, givenDate, reason, emi, createdById: me.id },
  });
  revalidatePath(`/employees/${employeeId}`);
  return { success: await bt("Advance recorded 🪙") };
}

/** Staff: delete an advance that has NOT been partially repaid yet. */
export async function deleteAdvanceAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const id = String(formData.get("advanceId") ?? "");
  const adv = await db.advance.findFirst({ where: { id, companyId: me.companyId } });
  if (!adv) return { error: await bt("Advance not found.") };
  if (adv.repaid > 0) return { error: await bt("Recovery already started — cannot delete (adjust in payroll instead).") };
  await db.advance.delete({ where: { id: adv.id } });
  revalidatePath(`/employees/${adv.employeeId}`);
  return { success: await bt("Advance removed.") };
}
