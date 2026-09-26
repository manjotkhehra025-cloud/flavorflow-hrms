"use server";
import { bt } from "@/lib/i18n";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff, requireUser } from "@/lib/auth";
import type { ActionState } from "./auth";

const LETTER_TYPES = new Set(["EXPERIENCE", "JOINING", "KYC", "DUTY"]);

export async function createLetterAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const employeeId = formData.get("employeeId") as string;
  const type = (formData.get("type") as string)?.toUpperCase();
  const issuedTo = (formData.get("issuedTo") as string)?.trim() || null;

  if (!employeeId) return { error: await bt("Employee missing.") };
  if (!LETTER_TYPES.has(type)) return { error: await bt("Choose a letter type.") };

  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  if (!emp) return { error: await bt("Employee not found.") };

  const year = new Date().getUTCFullYear();
  const letter = await db.$transaction(async (tx) => {
    const company = await tx.company.update({
      where: { id: me.companyId },
      data: { letterSeq: { increment: 1 } },
    });
    const serial = `${company.code}/HR/${year}/${String(company.letterSeq).padStart(4, "0")}`;
    return tx.letter.create({
      data: {
        companyId: me.companyId,
        employeeId,
        serial,
        type,
        issuedTo,
        createdBy: me.id,
      },
    });
  });

  revalidatePath(`/employees/${employeeId}`);
  revalidatePath(`/letters/${letter.id}`);
  return { success: `Letter ${letter.serial} ready 📄` };
}

/** Owner employee or staff: mint (or reuse) a public share token for a letter. */
export async function createLetterLinkAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const letterId = String(formData.get("letterId") ?? "");
  const letter = await db.letter.findFirst({
    where: { id: letterId, companyId: me.companyId },
  });
  if (!letter) return { error: await bt("Letter not found.") };
  if (me.role === "EMPLOYEE" && letter.employeeId !== me.employeeId) {
    return { error: await bt("You can only share your own letters.") };
  }
  const link = await db.letterLink.upsert({
    where: { letterId: letter.id },
    update: {},
    create: { letterId: letter.id, companyId: me.companyId },
  });
  return { success: `/share/letter/${link.token}` };
}

export async function deleteLetterAction(letterId: string) {
  const me = await requireStaff();
  const letter = await db.letter.findFirst({ where: { id: letterId, companyId: me.companyId } });
  if (!letter) return;
  await db.letter.delete({ where: { id: letter.id } });
  revalidatePath(`/employees/${letter.employeeId}`);
}
