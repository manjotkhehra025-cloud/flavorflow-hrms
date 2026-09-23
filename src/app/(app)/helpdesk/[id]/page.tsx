import { Pa } from "@/components/Pa";
import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { Badge } from "@/components/ui";
import { fmtDate, fmtTime } from "@/lib/utils";
import { CATEGORY_META, TICKET_TONE } from "@/lib/helpdesk";
import { setTicketStatusAction } from "@/actions/helpdesk";
import { ReplyBox } from "./ReplyBox";
import { MarkSeen } from "./MarkSeen";

export const dynamic = "force-dynamic";

export default async function TicketThreadPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireUser();
  const { id } = await params;
  const staff = me.role !== "EMPLOYEE";

  const t = await db.ticket.findFirst({
    where: { id, companyId: me.companyId },
    include: { employee: true, replies: { orderBy: { createdAt: "asc" } } },
  });
  if (!t) notFound();
  if (!staff && me.employeeId !== t.employeeId) notFound();

  const c = CATEGORY_META[t.category];

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <MarkSeen ticketId={t.id} />

      <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-5 text-white shadow-[var(--shadow-pop)]">
        <div className="pointer-events-none absolute -right-14 -top-14 h-44 w-44 rounded-full bg-teal-500/15 blur-3xl" />
        <div className="relative">
          <div className="flex items-center gap-2 text-xs">
            <Link href="/helpdesk" className="font-semibold text-slate-400 hover:text-white">{<Pa>‹ Helpdesk</Pa>}</Link>
            <span className="text-slate-600">·</span>
            <Badge tone={TICKET_TONE[t.status]}><Pa>{t.status === "IN_PROGRESS" ? "IN PROGRESS" : t.status}</Pa></Badge>
          </div>
          <h1 className="mt-2 text-lg font-extrabold leading-snug">{c.emoji} {t.subject}</h1>
          <p className="mt-1 text-xs text-slate-400">
            {t.employee.firstName} {t.employee.lastName} · <Pa>{c.label}</Pa> · {fmtDate(t.createdAt)}
          </p>
          {staff && t.status !== "CLOSED" && (
            <div className="mt-3 flex flex-wrap gap-2">
              {t.status !== "IN_PROGRESS" && (
                <form
                  action={async () => {
                    "use server";
                    await setTicketStatusAction(t.id, "IN_PROGRESS");
                  }}
                >
                  <button className="rounded-lg bg-amber-500/90 px-3 py-1.5 text-[11px] font-bold text-white transition hover:bg-amber-500 active:scale-95">{<Pa>In progress</Pa>}</button>
                </form>
              )}
              {t.status !== "RESOLVED" && (
                <form
                  action={async () => {
                    "use server";
                    await setTicketStatusAction(t.id, "RESOLVED");
                  }}
                >
                  <button className="rounded-lg bg-emerald-500 px-3 py-1.5 text-[11px] font-bold text-white transition hover:bg-emerald-400 active:scale-95">{<Pa>✓ Mark resolved</Pa>}</button>
                </form>
              )}
              <form
                action={async () => {
                  "use server";
                  await setTicketStatusAction(t.id, "CLOSED");
                }}
              >
                <button className="rounded-lg bg-white/10 px-3 py-1.5 text-[11px] font-bold text-slate-300 ring-1 ring-white/15 transition hover:bg-white/15 active:scale-95">{<Pa>Close</Pa>}</button>
              </form>
            </div>
          )}
        </div>
      </div>

      {/* Thread */}
      <div className="space-y-2.5 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-200/60">
        {t.replies.map((r) => {
          const mine = staff ? r.isStaff : !r.isStaff;
          return (
            <div key={r.id} className={`flex ${mine ? "justify-end" : "justify-start"}`}>
              <div className={`max-w-[85%] rounded-2xl px-3.5 py-2.5 ${mine ? "rounded-br-md bg-[#0a1628] text-white" : "rounded-bl-md bg-slate-100 text-slate-800"}`}>
                <p className={`mb-0.5 text-[10px] font-bold ${mine ? "text-emerald-400" : "text-emerald-700"}`}>
                  {r.isStaff ? `${r.authorName} · HR` : r.authorName}
                </p>
                <p className="whitespace-pre-line text-[13px] leading-relaxed">{r.body}</p>
                <p className={`mt-1 text-[9px] ${mine ? "text-slate-500" : "text-slate-400"}`}>{fmtDate(r.createdAt)} · {fmtTime(r.createdAt)}</p>
              </div>
            </div>
          );
        })}
      </div>

      {t.status === "CLOSED" ? (
        <p className="rounded-2xl bg-slate-100 px-4 py-3 text-center text-xs font-semibold text-slate-500">
          🔒 This ticket is closed — raise a new ticket for any new issue.
        </p>
      ) : (
        <ReplyBox ticketId={t.id} />
      )}
    </div>
  );
}
