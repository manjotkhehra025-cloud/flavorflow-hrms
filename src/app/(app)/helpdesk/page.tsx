import { Pa } from "@/components/Pa";
import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { Card, PageHeader, Badge, EmptyState } from "@/components/ui";
import { fmtDate } from "@/lib/utils";
import { RaiseTicketForm } from "./RaiseTicketForm";
import { CATEGORY_META, TICKET_TONE } from "@/lib/helpdesk";
import type { TicketStatus } from "@prisma/client";

export const dynamic = "force-dynamic";

export default async function HelpdeskPage({ searchParams }: { searchParams: Promise<{ tab?: string; f?: string }> }) {
  const me = await requireUser();
  const { tab, f } = await searchParams;
  const staff = me.role !== "EMPLOYEE";

  if (!me.employeeId) {
    return (
      <div>
        <PageHeader title={<Pa>Helpdesk 💬</Pa>} subtitle={<Pa>Complaints and suggestions — straight to HR</Pa>} />
        <Card className="p-5">
          <EmptyState icon="chat" title={<Pa>Account not linked</Pa>} hint={<Pa>First link your login to an employee profile using the dashboard 'Link your login' card — then Helpdesk will open.</Pa>} />
        </Card>
      </div>
    );
  }

  const activeTab = staff && tab !== "mine" ? "inbox" : "mine";
  const filter = ["OPEN", "IN_PROGRESS", "RESOLVED", "ALL"].includes(f ?? "") ? f! : "OPEN";

  const [myTickets, inboxTickets] = await Promise.all([
    db.ticket.findMany({
      where: { companyId: me.companyId, employeeId: me.employeeId },
      include: { replies: { orderBy: { createdAt: "desc" }, take: 1 } },
      orderBy: { updatedAt: "desc" },
    }),
    staff
      ? db.ticket.findMany({
          where: { companyId: me.companyId, ...(filter === "ALL" ? {} : { status: filter as TicketStatus }) },
          include: { employee: true, replies: { orderBy: { createdAt: "desc" }, take: 1 } },
          orderBy: { updatedAt: "desc" },
          take: 100,
        })
      : Promise.resolve([]),
  ]);

  const statusCounts = staff
    ? await db.ticket.groupBy({ by: ["status"], where: { companyId: me.companyId }, _count: { _all: true } })
    : [];
  const countOf = (s: string) => statusCounts.find((c) => c.status === s)?._count._all ?? 0;

  return (
    <div className="space-y-6">
      <PageHeader title={<Pa>Helpdesk 💬</Pa>} subtitle={staff ? <Pa>Team complaints & suggestions — reply and resolve</Pa> : <Pa>Complaints & suggestions — straight to HR</Pa>} />

      {staff && (
        <div className="flex gap-1 rounded-2xl bg-slate-200/60 p-1">
          <Link href="/helpdesk?tab=inbox" className={`flex flex-1 items-center justify-center gap-1.5 rounded-xl px-4 py-2 text-sm font-semibold transition ${activeTab === "inbox" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"}`}>
            🎫 <Pa>Team inbox</Pa>
            {countOf("OPEN") > 0 && <span className="flex h-5 min-w-5 items-center justify-center rounded-full bg-emerald-500 px-1.5 text-[10px] font-bold text-white">{countOf("OPEN")}</span>}
          </Link>
          <Link href="/helpdesk?tab=mine" className={`flex flex-1 items-center justify-center gap-1.5 rounded-xl px-4 py-2 text-sm font-semibold transition ${activeTab === "mine" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"}`}>
            💬 <Pa>My tickets</Pa>
          </Link>
        </div>
      )}

      {activeTab === "mine" && (
        <>
          <RaiseTicketForm />
          <Card className="p-5">
            <h3 className="mb-4 text-sm font-bold text-slate-900"><Pa>My tickets</Pa> ({myTickets.length})</h3>
            {myTickets.length === 0 ? (
              <EmptyState icon="chat" title={<Pa>No tickets yet</Pa>} hint={<Pa>Machine, salary, uniform, canteen or safety — raise one with the form above 💬</Pa>} />
            ) : (
              <ul className="space-y-2.5">
                {myTickets.map((t) => {
                  const c = CATEGORY_META[t.category];
                  const lp = t.replies[0];
                  const unreadStaffReply = lp && lp.isStaff && (!t.employeeSeenAt || lp.createdAt > t.employeeSeenAt);
                  return (
                    <li key={t.id}>
                      <Link href={`/helpdesk/${t.id}`} className="flex items-center gap-3 rounded-xl bg-slate-50 px-4 py-3 transition hover:bg-slate-100 active:scale-[0.99]">
                        <span className="text-xl">{c.emoji}</span>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2 text-sm font-semibold text-slate-800">
                            <span className="truncate">{t.subject}</span>
                            {unreadStaffReply && <span className="h-2 w-2 shrink-0 rounded-full bg-emerald-500" title="New reply from HR!" />}
                          </div>
                          <div className="text-xs text-slate-500">
                            <Pa>{c.label}</Pa> · {fmtDate(t.createdAt)}
                            {lp ? <> · <Pa>Last</Pa>: {lp.isStaff ? "HR" : <Pa>You</Pa>}</> : ""}
                          </div>
                        </div>
                        <Badge tone={TICKET_TONE[t.status]}><Pa>{t.status === "IN_PROGRESS" ? "IN PROGRESS" : t.status}</Pa></Badge>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>
        </>
      )}

      {activeTab === "inbox" && staff && (
        <Card className="p-5">
          <div className="mb-4 flex flex-wrap gap-1.5">
            {(["OPEN", "IN_PROGRESS", "RESOLVED", "ALL"] as const).map((s) => (
              <Link
                key={s}
                href={`/helpdesk?tab=inbox&f=${s}`}
                className={`rounded-full px-3 py-1.5 text-[11px] font-bold transition ${filter === s ? "bg-[#0a1628] text-white" : "bg-slate-100 text-slate-500 hover:bg-slate-200"}`}
              >
                {s === "IN_PROGRESS" ? "In progress" : s.charAt(0) + s.slice(1).toLowerCase()}
                {s !== "ALL" && <span className="ml-1 opacity-70">({countOf(s)})</span>}
              </Link>
            ))}
          </div>
          {inboxTickets.length === 0 ? (
            <EmptyState icon="check" title={<Pa>All clear 🎉</Pa>} hint={<Pa>No tickets in this filter.</Pa>} />
          ) : (
            <ul className="space-y-2.5">
              {inboxTickets.map((t) => {
                const c = CATEGORY_META[t.category];
                const lp = t.replies[0];
                const unreadEmpReply = lp && !lp.isStaff && (!t.staffSeenAt || lp.createdAt > t.staffSeenAt);
                return (
                  <li key={t.id}>
                    <Link href={`/helpdesk/${t.id}`} className="flex items-center gap-3 rounded-xl bg-slate-50 px-4 py-3 transition hover:bg-slate-100 active:scale-[0.99]">
                      <span className="text-xl">{c.emoji}</span>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 text-sm font-semibold text-slate-800">
                          <span className="truncate">{t.employee.firstName} {t.employee.lastName}: {t.subject}</span>
                          {unreadEmpReply && <span className="h-2 w-2 shrink-0 rounded-full bg-amber-500" title="New reply from employee!" />}
                        </div>
                        <div className="text-xs text-slate-500"><Pa>{c.label}</Pa> · {fmtDate(t.createdAt)}{lp ? <> · <Pa>Last</Pa>: {lp.isStaff ? (lp.authorName) : <Pa>Employee</Pa>}</> : ""}</div>
                      </div>
                      <Badge tone={TICKET_TONE[t.status]}><Pa>{t.status === "IN_PROGRESS" ? "IN PROGRESS" : t.status}</Pa></Badge>
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
        </Card>
      )}
    </div>
  );
}
