import { db } from "@/lib/db";

/**
 * Approval routing — who must approve an employee's requests.
 *
 * Route A (Production / Quality / Agriculture staff, official or yellow-card)
 *   → needs a colleague holding a "Senior Manager" designation.
 * Route B (Electrical / Instruments / Mechanical / Maintenance / Engineering)
 *   → needs "Assistant General Manager".
 * If the required head does NOT exist (no active employee with that
 * designation), the request automatically falls through to the super admin.
 */

const GROUP_A = ["production", "quality", "agriculture", "lab"];
const GROUP_B = ["electrical", "instruments", "mechanical", "maintenance", "engineering"];

export const SR_MGR_TITLE = /senior\s+manager/i;
export const AGM_TITLE = /assistant\s+general\s+manager/i;

type DeptLike = { name: string; parent?: { name: string } | null } | null;

/** Resolve which department-approval group an employee belongs to (parent-aware). */
export function routeGroup(employee: { category?: string; department?: DeptLike }): "A" | "B" | null {
  const names: string[] = [];
  if (employee.department?.name) names.push(employee.department.name.toLowerCase());
  if (employee.department?.parent?.name) names.push(employee.department.parent.name.toLowerCase());
  for (const g of GROUP_A) if (names.some((n) => n.includes(g))) return "A";
  for (const g of GROUP_B) if (names.some((n) => n.includes(g))) return "B";
  return null;
}

/** Does a head exist for the given route group (active official employee w/ login + matching designation)? */
export async function groupHeadExists(companyId: string, group: "A" | "B"): Promise<boolean> {
  const titleRegex = group === "A" ? SR_MGR_TITLE : AGM_TITLE;
  const heads = await db.employee.findMany({
    where: {
      companyId,
      status: "ACTIVE",
      designation: { title: { contains: group === "A" ? "Senior Manager" : "Assistant General Manager", mode: "insensitive" } },
      users: { some: { isActive: true } },
    },
    select: { id: true },
  });
  void titleRegex;
  return heads.length > 0;
}

/** True when `me` is allowed to decide a request filed by `emp` (designation-routing aware). */
export async function canDecideFor(me: {
  id: string;
  role: string;
  employeeId: string | null;
  companyId: string;
}, emp: { designation?: { title: string } | null; department?: DeptLike; companyId?: string }): Promise<boolean> {
  if (me.role === "ADMIN" || me.role === "HR") return true;
  if (!me.employeeId) return false;
  const group = routeGroup(emp as never);
  if (!group) return false;
  const cid = (emp as never as { companyId: string }).companyId ?? me.companyId;
  // Super-admin fallback: when the group head is VACANT, none of the
  // designation-based approvers exists — only admins see/handle it.
  if (!(await groupHeadExists(cid, group))) return false;
  const mine = await db.employee.findUnique({
    where: { id: me.employeeId },
    include: { designation: true },
  });
  const title = mine?.designation?.title ?? "";
  return group === "A" ? SR_MGR_TITLE.test(title) : AGM_TITLE.test(title);
}

/** Approver scope for the list view: what requests THIS user is allowed to see & decide. */
export async function approverScope(me: {
  role: string;
  employeeId: string | null;
  companyId: string;
}): Promise<"ALL" | "A" | "B" | null> {
  if (me.role === "ADMIN" || me.role === "HR") return "ALL";
  if (!me.employeeId) return null;
  const mine = await db.employee.findUnique({
    where: { id: me.employeeId },
    include: { designation: true },
  });
  const title = mine?.designation?.title ?? "";
  if (SR_MGR_TITLE.test(title)) return "A";
  if (AGM_TITLE.test(title)) return "B";
  return null;
}

/** Filter an employee list by the approver scope (parent-aware routeGroups). */
export function filterByScope<T extends { category?: string; department?: DeptLike }>(items: T[], scope: "ALL" | "A" | "B" | null): T[] {
  if (scope === "ALL") return items;
  if (!scope) return [];
  return items.filter((e) => routeGroup(e) === scope);
}
