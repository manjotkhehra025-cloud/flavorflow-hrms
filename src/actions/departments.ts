"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import type { ActionState } from "./auth";

/** Add a department; optional parentId makes it a SUB-department. */
export async function addDepartmentAction(formData: FormData) {
  const me = await requireStaff();
  const name = (formData.get("name") as string)?.trim();
  const parentId = ((formData.get("parentId") as string)?.trim() || null);
  if (!name) return;
  await db.department.upsert({
    where: { companyId_name: { companyId: me.companyId, name } },
    create: { companyId: me.companyId, name, parentId },
    update: { parentId },
  });
  revalidatePath("/departments");
}

export async function editDepartmentAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const id = String(formData.get("id") ?? "");
  const name = (formData.get("name") as string)?.trim();
  const parentId = ((formData.get("parentId") as string)?.trim() || null);
  if (!id || !name) return { error: await bt("Name required.") };
  if (parentId === id) return { error: await bt("A department can't be its own parent.") };
  await db.department.updateMany({ where: { id, companyId: me.companyId }, data: { name, parentId } });
  revalidatePath("/departments");
  return { success: await bt("Saved ✔") };
}

export async function deleteDepartmentAction(id: string) {
  const me = await requireStaff();
  if (me.role !== "ADMIN") return;
  await db.department.deleteMany({ where: { id, companyId: me.companyId } });
  revalidatePath("/departments");
}

export async function addDesignationAction(formData: FormData) {
  const me = await requireStaff();
  const title = (formData.get("title") as string)?.trim();
  const category = (formData.get("category") as string) ?? "BOTH";
  const departmentId = ((formData.get("departmentId") as string)?.trim() || null);
  if (!title) return;
  await db.designation.upsert({
    where: { companyId_title: { companyId: me.companyId, title } },
    create: {
      companyId: me.companyId,
      title,
      category: (["OFFICIAL", "YELLOW_CARD", "BOTH"].includes(category) ? category : "BOTH") as "OFFICIAL" | "YELLOW_CARD" | "BOTH",
      departmentId,
    },
    update: { category: (["OFFICIAL", "YELLOW_CARD", "BOTH"].includes(category) ? category : "BOTH") as "OFFICIAL" | "YELLOW_CARD" | "BOTH", departmentId },
  });
  revalidatePath("/departments");
}

export async function editDesignationAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const id = String(formData.get("id") ?? "");
  const title = (formData.get("title") as string)?.trim();
  const category = (formData.get("category") as string) ?? "BOTH";
  const departmentId = ((formData.get("departmentId") as string)?.trim() || null);
  if (!id || !title) return { error: await bt("Title required.") };
  await db.designation.updateMany({
    where: { id, companyId: me.companyId },
    data: {
      title,
      category: (["OFFICIAL", "YELLOW_CARD", "BOTH"].includes(category) ? category : "BOTH") as "OFFICIAL" | "YELLOW_CARD" | "BOTH",
      departmentId,
    },
  });
  revalidatePath("/departments");
  return { success: await bt("Saved ✔") };
}

export async function deleteDesignationAction(id: string) {
  const me = await requireStaff();
  if (me.role !== "ADMIN") return;
  await db.designation.deleteMany({ where: { id, companyId: me.companyId } });
  revalidatePath("/departments");
}

/** One-tap seed of the G.D. Foods plant structure user described. Idempotent upserts. */
export async function seedGdStructureAction() {
  const me = await requireStaff();
  const cid = me.companyId;

  const depts = ["Production", "Quality", "Engineering", "Electrical", "Agriculture", "Security", "Instruments", "Accounts"];
  // Only Lab under Quality stays a sub-department. Mechanical & General Store are
  // plain top-level departments per G.D. Foods' current structure.
  const subs: Array<[string, string]> = [
    ["Lab", "Quality"],
  ];
  const ids: Record<string, string> = {};
  for (const d of depts) {
    ids[d] = (await db.department.upsert({ where: { companyId_name: { companyId: cid, name: d } }, create: { companyId: cid, name: d }, update: {} })).id;
  }
  for (const [sub, parent] of subs) {
    ids[sub] = (await db.department.upsert({
      where: { companyId_name: { companyId: cid, name: sub } },
      create: { companyId: cid, name: sub, parentId: ids[parent] },
      update: { parentId: ids[parent] },
    })).id;
  }

  // Reset earlier sub mappings: Mechanical / General Store back to top level.
  for (const legacy of ["Mechanical", "General Store"]) {
    const row = await db.department.findFirst({ where: { companyId: cid, name: legacy } });
    if (!row) {
      await db.department.create({ data: { companyId: cid, name: legacy } });
    } else if (row.parentId) {
      await db.department.update({ where: { id: row.id }, data: { parentId: null } });
    }
    ids[legacy] = (await db.department.update({ where: { companyId_name: { companyId: cid, name: legacy } }, data: {} })).id;
  }


  const desigs: Array<[string, "OFFICIAL" | "YELLOW_CARD" | "BOTH", string | null]> = [
    // Official
    ["Director of Operations", "OFFICIAL", null],
    ["Assistant General Manager", "OFFICIAL", null],
    ["Senior Manager Production", "OFFICIAL", "Production"],
    ["Manager", "BOTH", null],
    ["Senior Executive", "OFFICIAL", null],
    ["Senior Quality Executive", "OFFICIAL", "Quality"],
    ["Quality Executive", "OFFICIAL", "Quality"],
    // Yellow Card
    ["Operator", "YELLOW_CARD", null],
    ["Lab Assistant", "YELLOW_CARD", "Lab"],
    ["Store Keeper", "YELLOW_CARD", "General Store"],
    ["Welder", "YELLOW_CARD", null],
    ["Plumber", "YELLOW_CARD", null],
    ["Electrician", "YELLOW_CARD", "Electrical"],
  ];
  for (const [title, cat, dept] of desigs) {
    await db.designation.upsert({
      where: { companyId_title: { companyId: cid, title } },
      create: { companyId: cid, title, category: cat, departmentId: dept ? ids[dept] ?? null : null },
      update: { category: cat, departmentId: dept ? ids[dept] ?? null : null },
    });
  }
  revalidatePath("/departments");
}
