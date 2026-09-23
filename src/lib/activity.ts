import { db } from "@/lib/db";

export type ActivityItem = { at: Date; actor: string; text: string; href: string; icon: "clock" | "leaf" | "badge" | "check" | "x" | "chat" };

/** Live activity feed, computed from real events — no storage needed. */
export async function getRecentActivity(
  me: { companyId: string; role: string; employeeId: string | null },
  take = 30
): Promise<ActivityItem[]> {
  const staff = me.role !== "EMPLOYEE";
  const mine = me.employeeId ?? "__none__";
  const empScope = staff ? {} : { employeeId: mine };

  const [att, leaves, passes, letters, posts] = await Promise.all([
    db.attendance.findMany({ where: { companyId: me.companyId, ...empScope, checkIn: { not: null } }, include: { employee: true }, orderBy: { checkIn: "desc" }, take }),
    db.leaveRequest.findMany({ where: { companyId: me.companyId, ...empScope, status: { not: "PENDING" } }, include: { employee: true }, orderBy: { decidedAt: "desc" }, take }),
    db.gatePass.findMany({ where: { companyId: me.companyId, ...empScope, status: { not: "PENDING" } }, include: { employee: true }, orderBy: { decidedAt: "desc" }, take }),
    db.letter.findMany({ where: { companyId: me.companyId, ...(staff ? {} : { employeeId: mine }) }, include: { employee: true }, orderBy: { createdAt: "desc" }, take: 10 }),
    db.socialPost.findMany({ where: { companyId: me.companyId }, include: { author: true }, orderBy: { createdAt: "desc" }, take: 10 }),
  ]);

  const items: ActivityItem[] = [];
  for (const a of att) {
    const nm = `${a.employee.firstName} ${a.employee.lastName ?? ""}`.trim();
    if (a.checkOut) items.push({ at: a.checkOut, actor: nm, text: "punched out for the day", href: "/attendance", icon: "clock" });
    items.push({ at: a.checkIn!, actor: nm, text: "punched in", href: "/attendance", icon: "clock" });
  }
  for (const l of leaves) {
    if (!l.decidedAt) continue;
    items.push({ at: l.decidedAt, actor: `${l.employee.firstName} ${l.employee.lastName ?? ""}`.trim(), text: `leave ${l.status.toLowerCase()} (${l.days}d)`, href: "/leaves", icon: l.status === "APPROVED" ? "check" : "x" });
  }
  for (const g of passes) {
    if (!g.decidedAt) continue;
    items.push({ at: g.decidedAt, actor: `${g.employee.firstName} ${g.employee.lastName ?? ""}`.trim(), text: `gate pass ${g.status.toLowerCase()}`, href: "/idcard", icon: "badge" });
  }
  for (const lt of letters) {
    items.push({ at: lt.createdAt, actor: `${lt.employee.firstName} ${lt.employee.lastName ?? ""}`.trim(), text: `${lt.type.toLowerCase()} letter issued (${lt.serial})`, href: `/letters/${lt.id}`, icon: "leaf" });
  }
  for (const p of posts) {
    items.push({ at: p.createdAt, actor: p.author.name, text: p.body.length > 80 ? p.body.slice(0, 77) + "…" : p.body, href: "/social", icon: "chat" });
  }
  items.sort((a, b) => b.at.getTime() - a.at.getTime());
  return items.slice(0, take);
}
