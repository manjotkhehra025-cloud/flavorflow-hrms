"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import type { ActionState } from "./auth";

const TYPES = new Set(["AADHAAR", "PAN", "BANK", "ESIC", "MEDICAL", "OTHER"]);

export async function addKycDocAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  let employeeId = me.employeeId;
  const forEmp = String(formData.get("employeeId") ?? "");
  if (forEmp && forEmp !== me.employeeId) {
    if (me.role === "EMPLOYEE") return { error: await bt("Not authorized.") };
    const target = await db.employee.findFirst({ where: { id: forEmp, companyId: me.companyId } });
    if (!target) return { error: await bt("Employee not found.") };
    employeeId = target.id;
  }
  if (!employeeId) return { error: await bt("Your login isn't linked to an employee profile.") };
  const docType = String(formData.get("docType") ?? "").toUpperCase();
  const refNumber = String(formData.get("refNumber") ?? "").trim();
  if (!TYPES.has(docType)) return { error: await bt("Pick a document type.") };
  if (refNumber.length < 4) return { error: await bt("Document number looks too short.") };
  await db.kycDoc.create({ data: { companyId: me.companyId, employeeId, docType, refNumber } });
  revalidatePath("/letters");
  return { success: await bt("Document saved to locker 🪪") };
}

export async function deleteKycDocAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const id = String(formData.get("kycDocId") ?? "");
  const doc = await db.kycDoc.findFirst({ where: { id, companyId: me.companyId } });
  if (!doc) return { error: await bt("Document not found.") };
  if (doc.employeeId !== me.employeeId && me.role === "EMPLOYEE") return { error: await bt("Not authorized.") };
  await db.kycDoc.delete({ where: { id } });
  revalidatePath("/letters");
  return { success: await bt("Document removed.") };
}
