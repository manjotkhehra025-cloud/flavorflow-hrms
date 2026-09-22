import { Pa } from "@/components/Pa";
import Link from "next/link";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { fmtDate, fmtTime, initials, cx } from "@/lib/utils";
import { Card, PageHeader, Badge, EmptyState } from "@/components/ui";
import { Icon } from "@/components/icons";
import { decideLeaveAction } from "@/actions/leaves";
import { decideGatePassAction, decidePunchRequestAction, verifyGatePassAction } from "@/actions/requests";

export const dynamic = "force-dynamic";

const TABS = [
  { key: "leave", label: "Leave Requests" },
  { key: "punch", label: "Manual Punch" },
  { key: "ot", label: "Overtime (OT)" },
  { key: "gate", label: "Gate Pass" },
] as const;

export default async function ApprovalsPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const me = await requireStaff();
  const { tab } = await searchParams;
  const active = TABS.some((t) => t.key === tab) ? (tab as (typeof TABS)[number]["key"]) : "leave";

  const [leaves, punches, gates] = await Promise.all([
    db.leaveRequest.findMany({
      where: { companyId: me.companyId, status: "PENDING" },
      include: { employee: true, leaveType: true },
      orderBy: { createdAt: "asc" },
    }),
    db.punchRequest.findMany({
      where: { companyId: me.companyId, status: "PENDING" },
      include: { employee: true },
      orderBy: { createdAt: "asc" },
    }),
    db.gatePass.findMany({
      where: { companyId: me.companyId, status: { in: ["PENDING", "APPROVED"] }, entryVerifiedAt: null },
      include: { employee: true },
      orderBy: { createdAt: "asc" },
    }),
  ]);

  const punchManual = punches.filter((p) => p.type !== "OT");
  const punchOT = punches.filter((p) => p.type === "OT");
  const gatesPending = gates.filter((g) => g.status === "PENDING");
  const counts: Record<string, number> = {
    leave: leaves.length,
    punch: punchManual.length,
    ot: punchOT.length,
    gate: gatesPending.length,
  };
  const total = Object.values(counts).reduce((a, b) => a + b, 0);

  return (
    <div>
      <PageHeader title={<Pa>Pending Approvals</Pa>} subtitle={<><Pa>Review, authorize, or decline requests</Pa> · {total} <Pa>waiting</Pa></>} />

      {/* Tabs */}
      <div className="mb-6 flex gap-1 overflow-x-auto rounded-2xl bg-slate-200/60 p-1">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={`/approvals?tab=${t.key}`}
            className={cx(
              "flex min-w-max flex-1 items-center justify-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition",
              active === t.key ? "bg-white text-slate-900 shadow-sm" : "text-slate-500 hover:text-slate-700"
            )}
          >
            <Pa>{t.label}</Pa>
            <span className={cx(
              "flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[10px] font-bold",
              counts[t.key] > 0 ? "bg-emerald-500 text-white" : "bg-slate-300/70 text-slate-500"
            )}>
              {counts[t.key]}
            </span>
          </Link>
        ))}
      </div>

      <Card className="p-5">
        {/* LEAVE TAB */}
        {active === "leave" && (
          leaves.length === 0 ? (
            <Blank />
          ) : (
            <ul className="space-y-2.5">
              {leaves.map((l) => (
                <li key={l.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 px-4 py-3">
                  <Avatar name={`${l.employee.firstName} ${l.employee.lastName}`} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-semibold text-slate-800">{l.employee.firstName} {l.employee.lastName}</div>
                    <div className="text-xs text-slate-500">
                      {l.leaveType.name} · {fmtDate(l.fromDate)} – {fmtDate(l.toDate)} ({l.days}d){l.reason ? ` · "${l.reason}"` : ""}
                    </div>
                  </div>
                  <Actions
                    approve={async () => {
                      "use server";
                      await decideLeaveAction(l.id, "APPROVED");
                    }}
                    reject={async () => {
                      "use server";
                      await decideLeaveAction(l.id, "REJECTED");
                    }}
                  />
                </li>
              ))}
            </ul>
          )
        )}

        {/* MANUAL PUNCH TAB */}
        {active === "punch" && (
          punchManual.length === 0 ? (
            <Blank />
          ) : (
            <ul className="space-y-2.5">
              {punchManual.map((p) => (
                <li key={p.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 px-4 py-3">
                  <Avatar name={`${p.employee.firstName} ${p.employee.lastName}`} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-semibold text-slate-800">
                      {p.employee.firstName} {p.employee.lastName} · <Badge tone="blue">{p.type === "MANUAL_IN" ? "Punch In" : "Punch Out"}</Badge>
                    </div>
                    <div className="text-xs text-slate-500">
                      {fmtDate(p.date)} at {p.time}{p.reason ? ` · "${p.reason}"` : ""}
                    </div>
                  </div>
                  <Actions
                    approve={async () => {
                      "use server";
                      await decidePunchRequestAction(p.id, true);
                    }}
                    reject={async () => {
                      "use server";
                      await decidePunchRequestAction(p.id, false);
                    }}
                  />
                </li>
              ))}
            </ul>
          )
        )}

        {/* OT TAB */}
        {active === "ot" && (
          punchOT.length === 0 ? (
            <Blank />
          ) : (
            <ul className="space-y-2.5">
              {punchOT.map((p) => (
                <li key={p.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 px-4 py-3">
                  <Avatar name={`${p.employee.firstName} ${p.employee.lastName}`} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-semibold text-slate-800">
                      {p.employee.firstName} {p.employee.lastName} · <Badge tone="amber">OT {p.hours}h</Badge>
                    </div>
                    <div className="text-xs text-slate-500">{fmtDate(p.date)}{p.reason ? ` · "${p.reason}"` : ""}</div>
                  </div>
                  <Actions
                    approve={async () => {
                      "use server";
                      await decidePunchRequestAction(p.id, true);
                    }}
                    reject={async () => {
                      "use server";
                      await decidePunchRequestAction(p.id, false);
                    }}
                  />
                </li>
              ))}
            </ul>
          )
        )}

        {/* GATE PASS TAB */}
        {active === "gate" && (
          gates.length === 0 ? (
            <Blank />
          ) : (
            <ul className="space-y-2.5">
              {gates.map((g) => (
                <li key={g.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 px-4 py-3">
                  <Avatar name={`${g.employee.firstName} ${g.employee.lastName}`} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-semibold text-slate-800">
                      {g.employee.firstName} {g.employee.lastName} · <Badge tone={g.status === "APPROVED" ? "green" : "amber"}>{g.status}</Badge>
                    </div>
                    <div className="text-xs text-slate-500">
                      {fmtDate(g.date)} · Exit {g.exitAt}{g.returnAt ? ` · Return ${g.returnAt}` : ""}{g.reason ? ` · "${g.reason}"` : ""}
                    </div>
                  </div>
                  {g.status === "PENDING" ? (
                    <Actions
                      approve={async () => {
                        "use server";
                        await decideGatePassAction(g.id, true);
                      }}
                      reject={async () => {
                        "use server";
                        await decideGatePassAction(g.id, false);
                      }}
                    />
                  ) : (
                    <form
                      action={async () => {
                        "use server";
                        await verifyGatePassAction(g.id);
                      }}
                    >
                      <button className="flex items-center gap-1.5 rounded-lg bg-sky-500 px-3 py-1.5 text-xs font-bold text-white hover:bg-sky-600 active:scale-95">
                        <Icon name="check" className="h-3.5 w-3.5" /> Mark Entry Verified
                      </button>
                    </form>
                  )}
                </li>
              ))}
            </ul>
          )
        )}
      </Card>
    </div>
  );
}

function Blank() {
  return (
    <EmptyState icon="check" title={<Pa>No pending requests</Pa>} hint={<Pa>All clear — no waiting requests ✨</Pa>} />
  );
}

function Avatar({ name }: { name: string }) {
  return (
    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#0a1628] text-xs font-bold text-emerald-400">
      {initials(name)}
    </span>
  );
}

function Actions({ approve, reject }: { approve: () => Promise<void>; reject: () => Promise<void> }) {
  return (
    <div className="flex gap-2">
      <form action={approve}>
        <button className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-bold text-white hover:bg-emerald-600 active:scale-95">{<Pa>Approve</Pa>}</button>
      </form>
      <form action={reject}>
        <button className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-bold text-slate-600 hover:bg-slate-50 active:scale-95">{<Pa>Reject</Pa>}</button>
      </form>
    </div>
  );
}
