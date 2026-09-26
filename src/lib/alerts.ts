import { db } from "@/lib/db";
import { t, getRequestLang, type Lang } from "@/lib/i18n";
import { approverScope, filterByScope } from "@/lib/approve-routing";

export type AlertItem = {
  kind: string;
  title: string;
  body: string;
  href: string;
  /** Flutter route: `tab:approvals` | `tab:leaves` | `/attendance` | … */
  appPath: string;
  at: Date | null;
};

type Me = { companyId: string; role: string; employeeId: string | null };

const empInc = { department: { include: { parent: true } } } as const;

function appPathFor(href: string): string {
  if (href.startsWith("/approvals")) return "tab:approvals";
  if (href.startsWith("/leaves")) return "tab:leaves";
  if (href.startsWith("/attendance")) return "/attendance";
  if (href.startsWith("/idcard")) return "/idcard";
  if (href.startsWith("/roster")) return "/roster";
  return "/home";
}

function push(items: AlertItem[], item: Omit<AlertItem, "appPath">) {
  items.push({ ...item, appPath: appPathFor(item.href) });
}

/**
 * Bell alerts.
 * Approvers (ADMIN/HR **and** designation heads who are still role EMPLOYEE)
 * see pending requests in their route group — not the whole company.
 * Anyone linked to an employee also sees decisions on their own requests
 * from the last 7 days.
 */
export async function getAlerts(me: Me, opts?: { lang?: Lang }): Promise<{ count: number; items: AlertItem[] }> {
  const lang = opts?.lang ?? (await getRequestLang());
  const tr = (en: string) => t(lang, en);
  const items: AlertItem[] = [];
  const scope = await approverScope(me);

  if (scope) {
    const [leaves, punches, gates, swaps] = await Promise.all([
      db.leaveRequest.findMany({
        where: { companyId: me.companyId, status: "PENDING" },
        include: { employee: { include: empInc } },
        orderBy: { createdAt: "desc" },
        take: 20,
      }),
      db.punchRequest.findMany({
        where: { companyId: me.companyId, status: "PENDING" },
        include: { employee: { include: empInc } },
        orderBy: { createdAt: "desc" },
        take: 20,
      }),
      db.gatePass.findMany({
        where: { companyId: me.companyId, status: "PENDING" },
        include: { employee: { include: empInc } },
        orderBy: { createdAt: "desc" },
        take: 20,
      }),
      db.shiftSwapRequest.findMany({
        where: { companyId: me.companyId, status: "PENDING" },
        include: { requester: { include: empInc }, peer: true },
        orderBy: { createdAt: "desc" },
        take: 20,
      }),
    ]);

    const inScope = (e: { category?: string; department?: unknown; id?: string }) =>
      e.id !== me.employeeId && (scope === "ALL" || filterByScope([e as never], scope).length === 1);

    for (const r of leaves) {
      if (!inScope(r.employee)) continue;
      push(items, {
        kind: "leaf",
        title: tr("Leave request"),
        body: `${r.employee.firstName} ${r.employee.lastName ?? ""} · ${r.days}${r.halfDay ? " (½)" : ""}d`,
        href: "/approvals",
        at: r.createdAt,
      });
    }
    for (const r of punches) {
      if (!inScope(r.employee)) continue;
      push(items, {
        kind: "clock",
        title: r.type === "OT" ? tr("OT request") : tr("Manual punch"),
        body: `${r.employee.firstName} · ${r.type === "MANUAL_IN" ? tr("Punch In") : r.type === "MANUAL_OUT" ? tr("Punch Out") : r.type}${r.hours ? ` ${r.hours}h` : ""}`,
        href: "/approvals",
        at: r.createdAt,
      });
    }
    for (const r of gates) {
      if (!inScope(r.employee)) continue;
      push(items, {
        kind: "badge",
        title: tr("Gate pass"),
        body: `${r.employee.firstName} · ${r.exitAt}`,
        href: "/approvals",
        at: r.createdAt,
      });
    }
    for (const r of swaps) {
      if (!inScope(r.requester)) continue;
      push(items, {
        kind: "calendar",
        title: tr("Shift swap"),
        body: `${r.requester.firstName} ↔ ${r.peer.firstName}`,
        href: "/roster?tab=swaps",
        at: r.createdAt,
      });
    }
  }

  if (me.employeeId) {
    const since = new Date(Date.now() - 7 * 86400000);
    const [leaves, punches, gates, swaps] = await Promise.all([
      db.leaveRequest.findMany({
        where: { companyId: me.companyId, employeeId: me.employeeId, status: { not: "PENDING" }, decidedAt: { gte: since } },
        orderBy: { decidedAt: "desc" },
        take: 10,
      }),
      db.punchRequest.findMany({
        where: { companyId: me.companyId, employeeId: me.employeeId, status: { not: "PENDING" }, decidedAt: { gte: since } },
        orderBy: { decidedAt: "desc" },
        take: 10,
      }),
      db.gatePass.findMany({
        where: { companyId: me.companyId, employeeId: me.employeeId, status: { not: "PENDING" }, decidedAt: { gte: since } },
        orderBy: { decidedAt: "desc" },
        take: 10,
      }),
      db.shiftSwapRequest.findMany({
        where: { companyId: me.companyId, requesterId: me.employeeId, status: { not: "PENDING" }, decidedAt: { gte: since } },
        include: { peer: true },
        orderBy: { decidedAt: "desc" },
        take: 10,
      }),
    ]);
    const verdict = (ok: boolean) => (ok ? tr("approved ✔") : tr("declined ✖"));
    for (const r of leaves) {
      push(items, {
        kind: r.status === "APPROVED" ? "check" : "x",
        title: `${tr("Leave")} ${verdict(r.status === "APPROVED")}`,
        body: r.reason ?? "",
        href: "/leaves",
        at: r.decidedAt,
      });
    }
    for (const r of punches) {
      const punchKind = r.type === "OT" ? "OT" : tr("Manual punch");
      push(items, {
        kind: r.status === "APPROVED" ? "check" : "x",
        title: `${punchKind} ${verdict(r.status === "APPROVED")}`,
        body: r.reason ?? "",
        href: "/attendance",
        at: r.decidedAt,
      });
    }
    for (const r of gates) {
      push(items, {
        kind: r.status === "APPROVED" ? "check" : "x",
        title: `${tr("Gate pass")} ${verdict(r.status === "APPROVED")}`,
        body: r.reason ?? "",
        href: "/idcard",
        at: r.decidedAt,
      });
    }
    for (const r of swaps) {
      push(items, {
        kind: r.status === "APPROVED" ? "check" : "x",
        title: `${tr("Shift swap")} ${verdict(r.status === "APPROVED")}`,
        body: r.peer.firstName,
        href: "/roster",
        at: r.decidedAt,
      });
    }
  }

  items.sort((a, b) => (b.at?.getTime() ?? 0) - (a.at?.getTime() ?? 0));
  const sliced = items.slice(0, 14);
  return { count: sliced.length, items: sliced };
}
