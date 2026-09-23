"use client";

import { useActionState, useRef, useTransition } from "react";
import { Tt } from "@/components/LangCtx";
import { createSwapRequestAction, decideSwapAction } from "@/actions/swaps";
import { cx } from "@/lib/utils";

type Swap = { id: string; requester: string; peer: string; date: string; note: string | null; status: "PENDING" | "APPROVED" | "REJECTED" | "CANCELLED"; mine: boolean };
type Props = { staff: boolean; myEmployeeId: string | null; peers: { id: string; name: string }[]; swaps: Swap[] };

const STATUS_CHIP: Record<string, string> = {
  PENDING: "bg-amber-100 text-amber-700",
  APPROVED: "bg-emerald-100 text-emerald-700",
  REJECTED: "bg-rose-100 text-rose-600",
  CANCELLED: "bg-slate-100 text-slate-500",
};

export function SwapPanel({ staff, myEmployeeId, peers, swaps }: Props) {
  const [state, formAction, pending] = useActionState(createSwapRequestAction, {});
  const [deciding, startTransition] = useTransition();
  const formRef = useRef<HTMLFormElement>(null);
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  const pendingList = swaps.filter((s) => s.status === "PENDING");
  const history = swaps.filter((s) => s.status !== "PENDING");

  return (
    <div className="space-y-4">
      {/* request form (employees with linked profile) */}
      {myEmployeeId && (
        <form
          ref={formRef}
          action={async (fd) => { await formAction(fd); formRef.current?.reset(); }}
          className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"
        >
          <h2 className="text-sm font-extrabold text-slate-800"><Tt>Request a shift swap</Tt></h2>
          <p className="mt-0.5 text-xs text-slate-500"><Tt>Swap your duty with a teammate for one day — HR must approve.</Tt></p>
          <div className="mt-3 grid gap-2.5 sm:grid-cols-3">
            <label className="block">
              <span className="mb-1 block text-[11px] font-bold uppercase tracking-wide text-slate-400"><Tt>Date</Tt></span>
              <input type="date" name="date" required min={tomorrow} className="w-full rounded-xl bg-slate-50 px-3 py-2 text-sm outline-none ring-1 ring-inset ring-slate-200 focus:ring-2 focus:ring-emerald-400" />
            </label>
            <label className="block sm:col-span-2">
              <span className="mb-1 block text-[11px] font-bold uppercase tracking-wide text-slate-400"><Tt>Swap with</Tt></span>
              <select name="peerId" required defaultValue="" className="w-full rounded-xl bg-slate-50 px-3 py-2 text-sm outline-none ring-1 ring-inset ring-slate-200 focus:ring-2 focus:ring-emerald-400">
                <option value="" disabled>— pick teammate —</option>
                {peers.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </label>
          </div>
          <input name="note" maxLength={200} placeholder="Reason (optional)…" className="mt-2.5 w-full rounded-xl bg-slate-50 px-3 py-2 text-sm outline-none ring-1 ring-inset ring-slate-200 focus:ring-2 focus:ring-emerald-400" />
          <div className="mt-2.5 flex items-center justify-between">
            <span className="text-xs font-semibold">{state?.error ? <span className="text-rose-600">{state.error}</span> : <span className="text-emerald-600">{state?.success}</span>}</span>
            <button disabled={pending} className="rounded-xl bg-[#0a1628] px-4 py-2 text-xs font-extrabold text-emerald-300 shadow transition hover:brightness-110 disabled:opacity-50">{pending ? "…" : <Tt>Send request</Tt>}</button>
          </div>
        </form>
      )}

      {/* pending queue */}
      <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
        <header className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-4 py-2.5">
          <h2 className="text-sm font-extrabold text-slate-800"><Tt>Pending swaps</Tt></h2>
          {pendingList.length > 0 && <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-extrabold text-amber-700">{pendingList.length}</span>}
        </header>
        <ul className="divide-y divide-slate-100">
          {pendingList.map((s) => (
            <li key={s.id} className="flex items-center gap-3 px-4 py-3">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-[#0a1628] text-base"></span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-bold text-slate-800">{s.requester} <span className="text-slate-400">↔</span> {s.peer}</p>
                <p className="truncate text-xs text-slate-500">{s.date}{s.note ? ` · ${s.note}` : ""}</p>
              </div>
              {staff ? (
                <div className="flex gap-1.5">
                  <button
                    disabled={deciding}
                    onClick={() => startTransition(async () => { await decideSwapAction(s.id, true); })}
                    className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-extrabold text-white shadow disabled:opacity-50"
                  >✔ <Tt>Approve</Tt></button>
                  <button
                    disabled={deciding}
                    onClick={() => startTransition(async () => { await decideSwapAction(s.id, false); })}
                    className="rounded-lg bg-rose-100 px-3 py-1.5 text-xs font-extrabold text-rose-600 disabled:opacity-50"
                  >✖ <Tt>Reject</Tt></button>
                </div>
              ) : (
                <span className={cx("rounded-full px-2.5 py-1 text-[11px] font-extrabold", STATUS_CHIP[s.status])}><Tt>Waiting…</Tt></span>
              )}
            </li>
          ))}
          {pendingList.length === 0 && <li className="px-4 py-8 text-center text-sm text-slate-400"><Tt>No pending swap requests</Tt></li>}
        </ul>
      </section>

      {/* history */}
      {history.length > 0 && (
        <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <header className="border-b border-slate-100 bg-slate-50 px-4 py-2.5">
            <h2 className="text-sm font-extrabold text-slate-800"><Tt>History</Tt></h2>
          </header>
          <ul className="divide-y divide-slate-100">
            {history.map((s) => (
              <li key={s.id} className="flex items-center gap-3 px-4 py-2.5">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[13px] font-semibold text-slate-700">{s.requester} ↔ {s.peer} · {s.date}</p>
                </div>
                <span className={cx("rounded-full px-2.5 py-1 text-[10px] font-extrabold uppercase", STATUS_CHIP[s.status])}>{s.status}</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
