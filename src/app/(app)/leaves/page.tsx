import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { fmtDate } from "@/lib/utils";
import { Card, PageHeader, Badge, inputCls, btnBrand } from "@/components/ui";
import { decideLeaveAction, cancelLeaveAction } from "@/actions/leaves";
import { getLeaveBalances } from "@/lib/balances";
import { ApplyLeaveForm } from "./ApplyLeaveForm";

export const dynamic = "force-dynamic";

function LeaveBadge({ status }: { status: string }) {
  const tone =
    status === "APPROVED" ? "green" : status === "REJECTED" ? "red" : status === "CANCELLED" ? "slate" : "amber";
  return <Badge tone={tone as "green" | "red" | "slate" | "amber"}>{status}</Badge>;
}

export default async function LeavesPage() {
  const me = await requireUser();
  const staff = me.role !== "EMPLOYEE";

  const [leaveTypes, myLeaves, pending, balances] = await Promise.all([
    db.leaveType.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" } }),
    me.employeeId
      ? db.leaveRequest.findMany({
          where: { employeeId: me.employeeId },
          include: { leaveType: true },
          orderBy: { createdAt: "desc" },
          take: 20,
        })
      : Promise.resolve([]),
    staff
      ? db.leaveRequest.findMany({
          where: { companyId: me.companyId, status: "PENDING" },
          include: { employee: true, leaveType: true },
          orderBy: { createdAt: "asc" },
        })
      : Promise.resolve([]),
    me.employeeId ? getLeaveBalances(me.employeeId, me.companyId) : Promise.resolve([]),
  ]);

  return (
    <div>
      <PageHeader title="Leaves" subtitle="Apply for time off and track approvals." />

      {/* My balance chips */}
      {me.employeeId && balances.length > 0 && (
        <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {balances.map((b) => (
            <Card key={b.leaveTypeId} className="p-4">
              <div className="text-[11px] font-semibold uppercase tracking-wide text-slate-400">{b.name}</div>
              <div className="mt-1 flex items-baseline gap-1">
                <span className="text-2xl font-extrabold text-slate-900">
                  {b.daysPerYear > 0 ? Math.max(b.daysPerYear - b.used, 0) : b.used}
                </span>
                <span className="text-xs text-slate-400">
                  {b.daysPerYear > 0 ? `/ ${b.daysPerYear} left` : "taken"}
                </span>
              </div>
              {b.daysPerYear > 0 && (
                <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-100">
                  <div
                    className="h-full rounded-full bg-amber-500 transition-all"
                    style={{ width: `${Math.min(100, (b.used / b.daysPerYear) * 100)}%` }}
                  />
                </div>
              )}
              {b.pending > 0 && (
                <div className="mt-1.5 text-[11px] font-semibold text-amber-600">{b.pending} day(s) pending</div>
              )}
            </Card>
          ))}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        {me.employeeId && (
          <Card className="p-5">
            <h3 className="mb-4 text-sm font-semibold text-slate-900">Apply for leave</h3>
            <ApplyLeaveForm leaveTypes={leaveTypes} />
          </Card>
        )}

        <Card className={me.employeeId ? "p-5 lg:col-span-2" : "p-5 lg:col-span-3"}>
          {staff && (
            <>
              <h3 className="mb-4 text-sm font-semibold text-slate-900">
                Needs your decision ({pending.length})
              </h3>
              {pending.length === 0 ? (
                <p className="mb-8 text-sm text-slate-500">No pending requests 🎉</p>
              ) : (
                <ul className="mb-8 space-y-3">
                  {pending.map((l) => (
                    <li key={l.id} className="rounded-xl border border-slate-200 p-4">
                      <div className="flex flex-wrap items-center justify-between gap-3">
                        <div>
                          <div className="text-sm font-semibold text-slate-900">
                            {l.employee.firstName} {l.employee.lastName}
                            <span className="ml-2 text-xs font-normal text-slate-500">({l.employee.code})</span>
                          </div>
                          <div className="mt-0.5 text-xs text-slate-500">
                            {l.leaveType.name} · {fmtDate(l.fromDate)} – {fmtDate(l.toDate)} · {l.days} day{l.days > 1 ? "s" : ""}
                          </div>
                          {l.reason && <div className="mt-1 text-sm text-slate-600">“{l.reason}”</div>}
                        </div>
                        <div className="flex gap-2">
                          <form action={decideLeaveAction.bind(null, l.id, "APPROVED")}>
                            <button className="rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-500">Approve</button>
                          </form>
                          <form action={decideLeaveAction.bind(null, l.id, "REJECTED")}>
                            <button className="rounded-lg border border-red-200 bg-white px-3 py-1.5 text-xs font-semibold text-red-600 hover:bg-red-50">Reject</button>
                          </form>
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}

          {me.employeeId && (
            <>
              <h3 className="mb-4 text-sm font-semibold text-slate-900">My requests</h3>
              {myLeaves.length === 0 ? (
                <p className="text-sm text-slate-500">You haven't applied for leave yet.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                        <th className="py-2 pr-4">Type</th>
                        <th className="py-2 pr-4">Dates</th>
                        <th className="py-2 pr-4">Days</th>
                        <th className="py-2 pr-4">Status</th>
                        <th className="py-2"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {myLeaves.map((l) => (
                        <tr key={l.id} className="border-b border-slate-100 last:border-0">
                          <td className="py-2.5 pr-4 font-medium text-slate-700">{l.leaveType.name}</td>
                          <td className="py-2.5 pr-4 text-slate-600">{fmtDate(l.fromDate)} – {fmtDate(l.toDate)}</td>
                          <td className="py-2.5 pr-4 text-slate-600">{l.days}</td>
                          <td className="py-2.5 pr-4"><LeaveBadge status={l.status} /></td>
                          <td className="py-2.5 text-right">
                            {l.status === "PENDING" && (
                              <form action={cancelLeaveAction.bind(null, l.id)}>
                                <button className="text-xs text-slate-400 hover:text-red-500 hover:underline">Cancel</button>
                              </form>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </>
          )}
        </Card>
      </div>
    </div>
  );
}
