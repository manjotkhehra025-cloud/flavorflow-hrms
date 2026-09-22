import Link from "next/link";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { fmtDate, initials } from "@/lib/utils";
import { Card, PageHeader, Badge, EmptyState, btnBrand } from "@/components/ui";
import { Icon } from "@/components/icons";
import { decideLeaveAction, cancelLeaveAction } from "@/actions/leaves";
import { getLeaveBalances, balanceRemaining } from "@/lib/balances";
import { ApplyLeaveForm } from "./ApplyLeaveForm";

export const dynamic = "force-dynamic";

const TONE: Record<string, "green" | "red" | "amber" | "slate"> = {
  APPROVED: "green",
  REJECTED: "red",
  PENDING: "amber",
  CANCELLED: "slate",
};

export default async function LeavesPage() {
  const me = await requireUser();
  const staff = me.role !== "EMPLOYEE";

  const myEmp = me.employeeId ? await db.employee.findUnique({ where: { id: me.employeeId } }) : null;

  const [leaveTypesAll, myLeaves, pending, balances] = await Promise.all([
    db.leaveType.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" } }),
    me.employeeId
      ? db.leaveRequest.findMany({
          where: { employeeId: me.employeeId },
          include: { leaveType: true },
          orderBy: { createdAt: "desc" },
          take: 10,
        })
      : Promise.resolve([]),
    staff
      ? db.leaveRequest.findMany({
          where: { companyId: me.companyId, status: "PENDING" },
          include: { employee: true, leaveType: true },
          orderBy: { createdAt: "asc" },
        })
      : Promise.resolve([]),
    myEmp ? getLeaveBalances({ id: myEmp.id, category: myEmp.category, joinDate: myEmp.joinDate }, me.companyId) : Promise.resolve([]),
  ]);

  const isYellow = myEmp?.category === "YELLOW_CARD";
  const leaveTypes = isYellow ? leaveTypesAll.filter((t) => /earned/i.test(t.name)) : leaveTypesAll;

  return (
    <div>
      <PageHeader title="Leaves Management" subtitle={isYellow ? "Yellow Card Staff · 15 EL per year" : "Apply for time off and track approvals."} />

      {/* Yellow Card policy card */}
      {isYellow && (
        <div className="mb-5 rounded-2xl border border-amber-200 bg-amber-50 p-5">
          <div className="flex items-start gap-3">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-amber-400/20 text-amber-600">
              <Icon name="badge" className="h-5 w-5" />
            </div>
            <div>
              <h3 className="text-sm font-bold text-amber-900">Yellow Card Staff Leave Policy</h3>
              <p className="mt-1 text-xs leading-relaxed text-amber-800">
                Yellow Card staff receive <b>15 Earned Leaves (EL)</b> per year, accrued monthly at{" "}
                <b>1.25 days per elapsed month</b> from your join month. Casual, Sick and Optional leaves are not applicable.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Balance cards (accrued vs used) */}
      {myEmp && balances.length > 0 && (
        <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {balances.map((b) => {
            const remaining = balanceRemaining(b);
            const entitled = b.accrued;
            const consumed = Math.max(b.used + b.adjusted, 0);
            const pct = b.quota === 0 ? 0 : Math.min(100, (consumed / Math.max(entitled, 1)) * 100);
            return (
              <Card key={b.leaveTypeId} className="relative p-5">
                <div className="flex items-center justify-between">
                  <div className="text-xs font-bold uppercase tracking-wide text-slate-400">{b.name}</div>
                  {staff && (
                    <Link href={`/employees/${myEmp.id}#adjust`} className="text-[11px] font-semibold text-emerald-600 hover:underline">
                      ✎ Edit
                    </Link>
                  )}
                </div>
                <div className="mt-2 flex items-baseline gap-1.5">
                  {remaining === null ? (
                    <>
                      <span className="text-3xl font-black text-emerald-600">{consumed}</span>
                      <span className="text-xs font-medium text-slate-400">taken · unlimited</span>
                    </>
                  ) : (
                    <>
                      <span className="text-3xl font-black text-emerald-600">{remaining}</span>
                      <span className="text-xs font-medium text-slate-400">days left</span>
                    </>
                  )}
                </div>
                <div className="mt-1 text-[11px] font-medium text-slate-500">
                  {b.quota === 0
                    ? "Unpaid / unlimited"
                    : isYellow
                      ? `Accrued: ${b.accrued} · Used: ${consumed}/${b.quota}`
                      : `Quota: ${b.quota} · Used: ${consumed}`}
                </div>
                {b.quota !== 0 && (
                  <div className="mt-2.5 h-1.5 overflow-hidden rounded-full bg-slate-100">
                    <div className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-emerald-600 transition-all" style={{ width: `${100 - pct}%` }} />
                  </div>
                )}
                {b.pending > 0 && (
                  <div className="mt-2 text-[11px] font-semibold text-amber-600">{b.pending} day(s) pending approval</div>
                )}
              </Card>
            );
          })}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-5">
        {/* Apply + my requests */}
        {me.employeeId && (
          <div className="space-y-6 lg:col-span-2">
            <Card className="p-5">
              <h3 className="mb-1 text-sm font-bold text-slate-900">Apply for leave</h3>
              <p className="mb-4 text-xs text-slate-500">Manager reviews and approves.</p>
              <ApplyLeaveForm leaveTypes={leaveTypes} />
            </Card>

            <Card className="p-5">
              <h3 className="mb-4 text-sm font-bold text-slate-900">My requests</h3>
              {myLeaves.length === 0 ? (
                <EmptyState icon="leaf" title="No leave requests yet" />
              ) : (
                <ul className="space-y-2.5">
                  {myLeaves.map((l) => (
                    <li key={l.id} className="rounded-xl bg-slate-50 px-4 py-3">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-sm font-semibold text-slate-800">{l.leaveType.name}</span>
                        <Badge tone={TONE[l.status]}>{l.status}</Badge>
                      </div>
                      <div className="mt-0.5 text-xs text-slate-500">
                        {fmtDate(l.fromDate)} – {fmtDate(l.toDate)} · {l.days}d{l.reason ? ` · "${l.reason}"` : ""}
                      </div>
                      {l.status === "PENDING" && (
                        <div className="mt-2 flex gap-2">
                          <form
                            action={async () => {
                              "use server";
                              await cancelLeaveAction(l.id);
                            }}
                          >
                            <button className="text-xs font-semibold text-red-500 hover:underline">Withdraw</button>
                          </form>
                        </div>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          </div>
        )}

        {/* Team pending approvals */}
        <div className={me.employeeId ? "lg:col-span-3" : "lg:col-span-5"}>
          {staff && (
            <Card className="p-5">
              <div className="mb-4 flex items-center justify-between">
                <h3 className="text-sm font-bold text-slate-900">Pending approvals ({pending.length})</h3>
                <Link href="/approvals" className="text-xs font-semibold text-emerald-600 hover:underline">Approvals hub →</Link>
              </div>
              {pending.length === 0 ? (
                <EmptyState icon="check" title="All clear!" hint="New leave requests will appear here" />
              ) : (
                <ul className="space-y-2.5">
                  {pending.map((l) => (
                    <li key={l.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 px-4 py-3">
                      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#0a1628] text-xs font-bold text-emerald-400">
                        {initials(`${l.employee.firstName} ${l.employee.lastName}`)}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="text-sm font-semibold text-slate-800">
                          {l.employee.firstName} {l.employee.lastName}
                        </div>
                        <div className="text-xs text-slate-500">
                          {l.leaveType.name} · {fmtDate(l.fromDate)} – {fmtDate(l.toDate)} ({l.days}d){l.reason ? ` · "${l.reason}"` : ""}
                        </div>
                      </div>
                      <div className="flex gap-2">
                        <form
                          action={async () => {
                            "use server";
                            await decideLeaveAction(l.id, "APPROVED");
                          }}
                        >
                          <button className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-bold text-white hover:bg-emerald-600 active:scale-95">Approve</button>
                        </form>
                        <form
                          action={async () => {
                            "use server";
                            await decideLeaveAction(l.id, "REJECTED");
                          }}
                        >
                          <button className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-bold text-slate-600 hover:bg-slate-50 active:scale-95">Reject</button>
                        </form>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          )}
          {!me.employeeId && !staff && (
            <Card className="p-6">
              <EmptyState icon="leaf" title="No employee profile linked" hint="Ask HR to link your login to an employee record" />
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
