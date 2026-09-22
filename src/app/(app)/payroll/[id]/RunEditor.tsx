"use client";
import { Tt, useT } from "@/components/LangCtx";

import { useActionState, useMemo, useState } from "react";
import { saveRowAdjustmentsAction, approveLockPayrollAction } from "@/actions/payroll";
import type { ActionState } from "@/actions/auth";
import { Card, btnBrand, btnGhost } from "@/components/ui";
import { fmtINR } from "@/lib/utils";

export type EditRow = {
  id: string; code: string; name: string; dept: string;
  salaryType: string; baseSalary: number | null; dailyRate: number | null;
  payableDays: number; presentDays: number; leaveDays: number; absentDays: number; offDays: number; lopDays: number;
  baseAmount: number; deductions: number;
  otHours: number; otRate: number; otAmount: number;
  advanceBalance: number; advanceRecover: number;
  otherDeduction: number; otherDeductionNote: string | null;
  otherEarning: number; otherEarningNote: string | null;
  paymentMode: string; bank: string | null;
  netPay: number; employeeId: string;
};

function net(r: EditRow, o: { ot?: number; adv?: number; ded?: number; earn?: number } = {}) {
  const ot = Math.round((o.ot ?? r.otHours) * r.otRate);
  const adv = o.adv ?? r.advanceRecover;
  const ded = o.ded ?? r.otherDeduction;
  const earn = o.earn ?? r.otherEarning;
  return { ot, net: Math.max(0, r.baseAmount + ot + earn - adv - ded) };
}

export function RunEditor({ runId, rows }: { runId: string; month: string; rows: EditRow[] }) {
  const ph = useT();
  const [state, action, pending] = useActionState<ActionState, FormData>(saveRowAdjustmentsAction, {});
  const [lockState, lockAction, lockPending] = useActionState<ActionState, FormData>(approveLockPayrollAction, {});
  const [edits, setEdits] = useState<Record<string, Partial<EditRow>>>({});
  const [confirmLock, setConfirmLock] = useState(false);

  const dirty = Object.keys(edits).length > 0;
  const merged = useMemo(() => rows.map((r) => ({ ...r, ...(edits[r.id] ?? {}) })), [rows, edits]);
  const grandNet = merged.reduce((s, r) => s + net(r).net, 0);

  function setField(id: string, k: keyof EditRow, v: number | string) {
    setEdits((e) => ({ ...e, [id]: { ...e[id], [k]: v as never } }));
  }

  function submit(fd: FormData) {
    const list = Object.entries(edits).map(([id, e]) => {
      const row = rows.find((r) => r.id === id)!;
      return {
        id,
        otHours: e.otHours ?? row.otHours,
        advanceRecover: e.advanceRecover ?? row.advanceRecover,
        otherDeduction: e.otherDeduction ?? row.otherDeduction,
        otherDeductionNote: e.otherDeductionNote ?? row.otherDeductionNote,
        otherEarning: e.otherEarning ?? row.otherEarning,
        otherEarningNote: e.otherEarningNote ?? row.otherEarningNote,
      };
    });
    fd.set("edits", JSON.stringify(list));
    return action(fd);
  }

  return (
    <div className="space-y-4">
      <Card className="p-0 overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-4 sm:px-6 py-3">
          <p className="text-xs text-slate-500"><Tt>Orange cells are editable — OT hours, advance recovery, other ± with notes.</Tt></p>
          <div className="text-xs"><Tt>Live total</Tt>: <b className="text-emerald-700">{fmtINR(grandNet)}</b></div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[900px] text-xs">
            <thead>
              <tr className="bg-slate-50 text-left text-[10px] font-bold uppercase tracking-wider text-slate-500">
                <th className="px-3 py-2.5"><Tt>Employee</Tt></th>
                <th className="px-2 py-2.5 text-center"><Tt>Days</Tt></th>
                <th className="px-2 py-2.5 text-right"><Tt>Base ₹</Tt></th>
                <th className="px-2 py-2.5 text-center"><Tt>OT hrs × rate</Tt></th>
                <th className="px-2 py-2.5 text-right"><Tt>Reward +</Tt></th>
                <th className="px-2 py-2.5 text-center"><Tt>Advance owed</Tt></th>
                <th className="px-2 py-2.5 text-center"><Tt>Advance ₹</Tt></th>
                <th className="px-2 py-2.5 text-right"><Tt>Other −</Tt></th>
                <th className="px-2 py-2.5 text-right"><Tt>Net ₹</Tt></th>
              </tr>
            </thead>
            <tbody>
              {merged.map((r) => {
                const n = net(r);
                return (
                  <tr key={r.id} className="border-t border-slate-100 align-top">
                    <td className="px-3 py-2.5">
                      <div className="font-bold text-slate-800">{r.code} · {r.name}</div>
                      <div className="text-[10px] text-slate-400">{r.dept} · {r.salaryType === "DAILY" ? <>{fmtINR(r.dailyRate ?? 0)}/<Tt>day</Tt></> : <>{fmtINR(r.baseSalary ?? 0)}/<Tt>mo</Tt></>}</div>
                    </td>
                    <td className="px-2 py-2.5 text-center whitespace-nowrap">
                      <span className="font-bold text-slate-700">{r.payableDays}</span>
                      <div className="text-[10px] text-slate-400">
                        P{r.presentDays} L{r.leaveDays} O{r.offDays}{r.lopDays > 0 ? ` · LOP ${r.lopDays}` : ""}
                      </div>
                    </td>
                    <td className="px-2 py-2.5 text-right font-semibold text-slate-700">{fmtINR(r.baseAmount)}
                      {r.deductions > 0 && <div className="text-[10px] text-rose-500">−{fmtINR(r.deductions)} <Tt>LOP</Tt></div>}
                    </td>
                    <td className="px-2 py-2.5">
                      <div className="flex items-center justify-center gap-1">
                        <input
                          type="number" min={0} max={200} step={0.5} value={r.otHours}
                          onChange={(e) => setField(r.id, "otHours", parseFloat(e.target.value) || 0)}
                          className="w-14 rounded-md border border-amber-300 bg-amber-50 px-1.5 py-1 text-center text-xs font-bold"
                        />
                        <span className="text-[10px] text-slate-400">×{r.otRate}</span>
                      </div>
                      {n.ot > 0 && <div className="text-center text-[10px] font-bold text-emerald-600">+{fmtINR(n.ot)}</div>}
                    </td>
                    <td className="px-2 py-2.5 text-right">
                      <input
                        type="number" min={0} value={r.otherEarning} placeholder="0" title={ph("Reward / bonus (+) reason")}
                        onChange={(e) => setField(r.id, "otherEarning", parseInt(e.target.value) || 0)}
                        className="w-16 rounded-md border border-amber-300 bg-amber-50 px-1.5 py-1 text-right text-xs font-bold"
                      />
                      {r.otherEarning > 0 && (
                        <input className="mt-1 w-full rounded border border-slate-200 px-1 py-0.5 text-[10px]" placeholder={ph("holi/attendance bonus…")}
                          defaultValue={r.otherEarningNote ?? ""} onBlur={(e) => setField(r.id, "otherEarningNote", e.target.value)} />
                      )}
                    </td>
                    <td className="px-2 py-2.5 text-center whitespace-nowrap text-[10px] text-slate-400">
                      <Tt>owed</Tt> <b className={r.advanceBalance > 0 ? "text-rose-600" : ""}>{fmtINR(r.advanceBalance)}</b>
                    </td>
                    <td className="px-2 py-2.5">
                      <input
                        type="number" min={0} max={r.advanceBalance} value={r.advanceRecover} disabled={r.advanceBalance === 0}
                        onChange={(e) => setField(r.id, "advanceRecover", Math.min(r.advanceBalance, parseInt(e.target.value) || 0))}
                        className="w-16 rounded-md border border-amber-300 bg-amber-50 px-1.5 py-1 text-right text-xs font-bold disabled:opacity-30"
                      />
                    </td>
                    <td className="px-2 py-2.5 text-right">
                      <input
                        type="number" min={0} value={r.otherDeduction}
                        onChange={(e) => setField(r.id, "otherDeduction", parseInt(e.target.value) || 0)}
                        className="w-16 rounded-md border border-amber-300 bg-amber-50 px-1.5 py-1 text-right text-xs font-bold"
                      />
                      {r.otherDeduction > 0 && (
                        <input className="mt-1 w-full rounded border border-slate-200 px-1 py-0.5 text-[10px]" placeholder={ph("reason: uniform…")}
                          defaultValue={r.otherDeductionNote ?? ""} onBlur={(e) => setField(r.id, "otherDeductionNote", e.target.value)} />
                      )}
                    </td>
                    <td className="px-2 py-2.5 text-right font-black text-emerald-700">{fmtINR(n.net)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>

      {state?.error && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>}
      {state?.success && <p className="rounded-lg bg-emerald-100 px-3 py-2 text-sm text-emerald-800">{state.success}</p>}
      {lockState?.error && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{lockState.error}</p>}

      <div className="flex flex-wrap gap-2">
        <form action={submit} className="contents">
          <input type="hidden" name="runId" value={runId} />
          <button type="submit" className={btnGhost} disabled={pending || !dirty}>
            💾 {pending ? <Tt>Saving…</Tt> : dirty ? <Tt>Save adjustments</Tt> : <Tt>Adjustments saved ✓</Tt>}
          </button>
        </form>
        <form action={lockAction} className="contents">
          <input type="hidden" name="runId" value={runId} />
          {confirmLock ? (
            <>
              <button type="submit" className={btnBrand} disabled={lockPending} onClick={(e) => { if (dirty) { e.preventDefault(); alert("You have unsaved adjustments — press Save first, then lock."); } }}>
                {lockPending ? "…" : <Tt>✅ Yes — approve & lock payroll</Tt>}
              </button>
              <button type="button" className={btnGhost} onClick={() => setConfirmLock(false)}><Tt>Cancel</Tt></button>
            </>
          ) : (
            <button type="button" className={btnBrand} onClick={() => setConfirmLock(true)}>🔒 <Tt>Approve & lock</Tt></button>
          )}
        </form>
      </div>
      <p className="text-[11px] text-slate-400"><Tt>Lock applies advance recovery to the ledger and publishes payslips to employees. After lock, nothing can change.</Tt></p>
    </div>
  );
}
