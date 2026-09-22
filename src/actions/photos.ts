"use server";
import { bt } from "@/lib/i18n";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { fsyncWrite, ensureUploadDir } from "@/lib/storage";
import type { ActionState } from "./auth";

const MAX_BYTES = 4 * 1024 * 1024;
const OK_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

export async function uploadEmployeePhotoAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const employeeId = formData.get("employeeId") as string;
  if (!employeeId) return { error: await bt("Employee missing.") };

  if (employeeId !== me.employeeId && me.role === "EMPLOYEE") {
    return { error: await bt("Not authorized.") };
  }
  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  if (!emp) return { error: await bt("Employee not found.") };

  const file = formData.get("photo") as File | null;
  if (!file || file.size === 0) return { error: await bt("Choose a photo first.") };
  if (!OK_TYPES.has(file.type)) return { error: await bt("Only JPG / PNG / WebP photos allowed.") };
  if (file.size > MAX_BYTES) return { error: await bt("Photo must be under 4 MB.") };

  try {
    await ensureUploadDir();
    const buf = Buffer.from(await file.arrayBuffer());
    const ext = file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg";
    await fsyncWrite(`${emp.id}.${ext}`, buf);
    // clean old extension variants
    for (const other of ["jpg", "png", "webp"]) {
      if (other !== ext) {
        const { rm } = await import("node:fs/promises");
        const { join } = await import("node:path");
        const { uploadDir } = await import("@/lib/storage");
        await rm(join(uploadDir(), `${emp.id}.${other}`), { force: true }).catch(() => {});
      }
    }
    const v = Date.now();
    await db.employee.update({
      where: { id: emp.id },
      data: { photoUrl: `/api/photo/${emp.id}?v=${v}`, photoExt: ext },
    });
  } catch (e) {
    return { error: await bt("Upload failed — try again.") };
  }

  revalidatePath(`/employees/${emp.id}`);
  revalidatePath("/idcard");
  revalidatePath("/employees");
  revalidatePath("/dashboard");
  revalidatePath("/tops");
  return { success: await bt("Photo uploaded 📸") };
}

export async function deleteEmployeePhotoAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const employeeId = formData.get("employeeId") as string;
  if (!employeeId) return { error: await bt("Employee missing.") };
  if (employeeId !== me.employeeId && me.role === "EMPLOYEE") return { error: await bt("Not authorized.") };
  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId } });
  if (!emp) return { error: await bt("Employee not found.") };

  const { rm } = await import("node:fs/promises");
  const { join } = await import("node:path");
  const { uploadDir } = await import("@/lib/storage");
  for (const ext of ["jpg", "png", "webp"]) {
    await rm(join(uploadDir(), `${emp.id}.${ext}`), { force: true }).catch(() => {});
  }
  await db.employee.update({ where: { id: emp.id }, data: { photoUrl: null, photoExt: null } });

  revalidatePath(`/employees/${emp.id}`);
  revalidatePath("/idcard");
  revalidatePath("/employees");
  revalidatePath("/dashboard");
  revalidatePath("/tops");
  return { success: await bt("Photo removed.") };
}
