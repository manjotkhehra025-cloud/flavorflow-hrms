import { Pa } from "@/components/Pa";

import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { Card, PageHeader, Badge } from "@/components/ui";
import { fmtDate } from "@/lib/utils";
import { Icon } from "@/components/icons";
import { LetterShareButtons } from "@/components/LetterShareButtons";
import { displayRef, LETTER_TYPE_LABELS } from "@/lib/letter-doc";

export const dynamic = "force-dynamic";

/**
 * My Letters — employees see their own letters; staff see every letter of the
 * company (with the employee's name). Mobile app mirrors this page exactly.
 */
export default async function MyLettersPage() {
  const me = await requireUser();
  const staff = me.role !== "EMPLOYEE";

  if (!staff && !me.employeeId) {
    return (
      <div className="space-y-4">
        <PageHeader title={<Pa>My Letters</Pa>} subtitle={<Pa>Experience · Joining · KYC · Duty pass</Pa>} />
        <Card className="p-8 text-center text-sm text-slate-400">
          <Pa>Your login is not linked to an employee profile yet — ask HR.</Pa>
        </Card>
      </div>
    );
  }

  const rows = await db.letter.findMany({
    where: { companyId: me.companyId, ...(staff ? {} : { employeeId: me.employeeId as string }) },
    include: { employee: { select: { id: true, code: true, firstName: true, lastName: true } } },
    orderBy: { createdAt: "desc" },
  });

  return (
    <div className="space-y-5">
      <PageHeader
        title={staff ? <Pa>Letters</Pa> : <Pa>My Letters</Pa>}
        subtitle={
          <>
            <Pa>Experience · Joining · KYC · Duty pass</Pa>
            <span className="ml-2 text-xs font-bold text-emerald-600">
              {rows.length} <Pa>letters issued</Pa>
            </span>
          </>
        }
      />

      {rows.length === 0 ? (
        <Card className="p-10 text-center">
          <div className="text-4xl">📄</div>
          <p className="mt-2 text-sm text-slate-500"><Pa>No letters issued yet</Pa></p>
          {!staff && (
            <p className="mt-1 text-xs text-slate-400"><Pa>HR generates them from your profile — they appear here instantly.</Pa></p>
          )}
        </Card>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {rows.map((l) => (
            <div
              key={l.id}
              className="group relative overflow-hidden rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:border-emerald-300 hover:shadow-md"
            >
              <div className="absolute -right-6 -top-6 h-20 w-20 rounded-full bg-emerald-50 transition group-hover:bg-emerald-100" />
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="truncate text-[10px] font-bold uppercase tracking-[0.14em] text-slate-400">
                    <Pa>{LETTER_TYPE_LABELS[l.type] ?? l.type}</Pa> · {fmtDate(l.createdAt)}
                  </div>
                  <div className="mt-1 truncate text-lg font-black text-slate-900">{displayRef(l.serial, l.employee.code)}</div>
                  {staff && (
                    <div className="mt-0.5 truncate text-xs font-semibold text-slate-500">
                      {l.employee.firstName} {l.employee.lastName} · {l.employee.code}
                    </div>
                  )}
                  {l.issuedTo && (
                    <div className="mt-1">
                      <Badge tone="blue">→ {l.issuedTo}</Badge>
                    </div>
                  )}
                </div>
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#0a1628] text-emerald-400">
                  <Icon name="doc" className="h-4.5 w-4.5" />
                </span>
              </div>
              <div className="mt-3 flex items-center justify-between gap-2">
                <Link href={`/letters/${l.id}`} target="_blank" className="inline-flex items-center gap-1 text-xs font-bold text-emerald-600 hover:underline">
                  <Icon name="printer" className="h-3.5 w-3.5" /> <Pa>Open / print</Pa>
                </Link>
                <LetterShareButtons letterId={l.id} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
