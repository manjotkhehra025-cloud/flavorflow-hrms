import { db } from "@/lib/db";
import { bt } from "@/lib/i18n";

export type AlertItem = { kind: string; title: string; body: string; href: string; at: Date | null };

/** Live-computed bell alerts — staff see pending queues; employees see recent decisions on their requests. */
export async function getAlerts(me: { companyId: string; role: string; employeeId: string | null }): Promise<{ count: number; items: AlertItem[] }> {
  const items: AlertItem[] = [];
  if (me.role !== "EMPLOYEE") {
    const [leaves, punches, gates, swaps] = await Promise.all([
      db.leaveRequest.findMany({ where: { companyId: me.companyId, status: "PENDING" }, include: { employee: true }, orderBy: { createdAt: "desc" }, take: 10 }),
      db.punchRequest.findMany({ where: { companyId: me.companyId, status: "PENDING" }, include: { employee: true }, orderBy: { createdAt: "desc" }, take: 10 }),
      db.gatePass.findMany({ where: { companyId: me.companyId, status: "PENDING" }, include: { employee: true }, orderBy: { createdAt: "desc" }, take: 10 }),
      db.shiftSwapRequest.findMany({ where: { companyId: me.companyId, status: "PENDING" }, include: { requester: true, peer: true }, orderBy: { createdAt: "desc" }, take: 10 }),
    ]);
    for (const r of leaves) items.push({ kind: "leaf", title: await bt("Leave request"), body: `${r.employee.firstName} ${r.employee.lastName ?? ""} · ${r.days}${r.halfDay ? " (½)" : ""}d`, href: "/approvals", at: r.createdAt });
    for (const r of punches) items.push({ kind: "clock", title: r.type === "OT" ? await bt("OT request") : await bt("Manual punch"), body: `${r.employee.firstName} · ${r.type === "MANUAL_IN" ? (await bt("Punch In")) : r.type === "MANUAL_OUT" ? (await bt("Punch Out")) : r.type}${r.hours ? ` ${r.hours}h` : ""}`, href: "/approvals", at: r.createdAt });
    for (const r of gates) items.push({ kind: "badge", title: await bt("Gate pass"), body: `${r.employee.firstName} · ${r.exitAt}`, href: "/approvals", at: r.createdAt });
    for (const r of swaps) items.push({ kind: "calendar", title: await bt("Shift swap"), body: `${r.requester.firstName} ↔ ${r.peer.firstName}`, href: "/roster?tab=swaps", at: r.createdAt });
  } else if (me.employeeId) {
    const since = new Date(Date.now() - 7 * 86400000);
    const [leaves, punches, gates] = await Promise.all([
      db.leaveRequest.findMany({ where: { companyId: me.companyId, employeeId: me.employeeId, status: { not: "PENDING" }, decidedAt: { gte: since } }, orderBy: { decidedAt: "desc" }, take: 10 }),
      db.punchRequest.findMany({ where: { companyId: me.companyId, employeeId: me.employeeId, status: { not: "PENDING" }, decidedAt: { gte: since } }, orderBy: { decidedAt: "desc" }, take: 10 }),
      db.gatePass.findMany({ where: { companyId: me.companyId, employeeId: me.employeeId, status: { not: "PENDING" }, decidedAt: { gte: since } }, orderBy: { decidedAt: "desc" }, take: 10 }),
    ]);
    for (const r of leaves) items.push({ kind: r.status === "APPROVED" ? "check" : "x", title: await bt("Leave") + " " + (r.status === "APPROVED" ? await bt("approved ✔") : await bt("declined ✖")), body: r.reason ?? "", href: "/leaves", at: r.decidedAt });
    for (const r of punches) items.push({ kind: r.status === "APPROVED" ? "check" : "x", title: (r.type === "OT" ? "OT " : "") + (r.status === "APPROVED" ? await bt("approved ✔") : await bt("declined ✖")), body: r.reason ?? "", href: "/attendance", at: r.decidedAt });
    for (const r of gates) items.push({ kind: r.status === "APPROVED" ? "check" : "x", title: await bt("Gate pass") + " " + (r.status === "APPROVED" ? await bt("approved ✔") : await bt("declined ✖")), body: r.reason ?? "", href: "/idcard", at: r.decidedAt });
  }
  items.sort((a, b) => (b.at?.getTime() ?? 0) - (a.at?.getTime() ?? 0));
  return { count: items.length, items: items.slice(0, 14) };
}
