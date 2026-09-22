"use client";

import { useState, useTransition, useRef } from "react";
import { useRouter } from "next/navigation";
import { addGoalAction, removeGoalAction, updateAchievedAction } from "@/actions/kra";

export type GoalDto = {
  id: string;
  title: string;
  weight: number;
  target: number;
  achieved: number;
  unit: string | null;
};

export function GoalEditor({
  cycleId, cycleStatus, employeeId, employeeName, employeeCode, goals, scorePct, weightOk,
}: {
  cycleId: string;
  cycleStatus: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string;
  goals: GoalDto[];
  scorePct: number | null;
  weightOk: boolean;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(goals.length > 0);
  const [busy, startTransition] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const titleRef = useRef<HTMLInputElement>(null);
  const weightRef = useRef<HTMLInputElement>(null);
  const targetRef = useRef<HTMLInputElement>(null);
  const unitRef = useRef<HTMLInputElement>(null);

  const editable = cycleStatus === "DRAFT" || cycleStatus === "OPEN";
  const achievedEditable = cycleStatus === "OPEN" || cycleStatus === "SCORING";
  const wsum = goals.reduce((a, b) => a + b.weight, 0);

  function run(fn: () => Promise<{ error?: string; success?: string }>) {
    setMsg(null);
    startTransition(async () => {
      const res = await fn();
      if (res?.error) setMsg(res.error);
      router.refresh();
    });
  }

  function addGoal() {
    const title = titleRef.current?.value.trim() ?? "";
    const weight = Number(weightRef.current?.value);
    const target = Number(targetRef.current?.value);
    const unit = unitRef.current?.value.trim() ?? "";
    run(() => addGoalAction(cycleId, employeeId, title, weight, target, unit));
    if (titleRef.current) titleRef.current.value = "";
    if (weightRef.current) weightRef.current.value = "";
    if (targetRef.current) targetRef.current.value = "";
    if (unitRef.current) unitRef.current.value = "";
  }

  return (
    <div className="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200/60">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center justify-between gap-3 px-4 py-3.5 text-left active:bg-slate-50"
      >
        <div className="flex items-center gap-3">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#0a1628] text-xs font-bold text-emerald-400">
            {employeeName.split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase()}
          </span>
          <div>
            <div className="text-sm font-bold text-slate-800">{employeeName} <span className="font-mono text-[10px] font-normal text-slate-400">{employeeCode}</span></div>
            <div className="text-[11px] text-slate-500">
              {goals.length} goals · weight {wsum}%{goals.length > 0 && !weightOk && <b className="text-rose-500"> (not 100%!)</b>}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {scorePct !== null && (
            <span className={`rounded-full px-2.5 py-1 text-[11px] font-extrabold ring-1 ${scorePct >= 75 ? "bg-emerald-50 text-emerald-700 ring-emerald-200" : scorePct >= 50 ? "bg-amber-50 text-amber-700 ring-amber-200" : "bg-rose-50 text-rose-600 ring-rose-200"}`}>
              {scorePct}%
            </span>
          )}
          <span className={`rounded-full px-2 py-0.5 text-[10px] font-bold ring-1 ${weightOk ? "bg-emerald-50 text-emerald-700 ring-emerald-200" : "bg-rose-50 text-rose-500 ring-rose-200"}`}>
            {weightOk ? "100% ✓" : "✗"}
          </span>
          <svg className={`h-4 w-4 text-slate-400 transition ${open ? "rotate-180" : ""}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="6 9 12 15 18 9" /></svg>
        </div>
      </button>

      {open && (
        <div className="space-y-2.5 border-t border-slate-100 p-4">
          {msg && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs font-medium text-red-600">{msg}</p>}
          {goals.map((g) => (
            <div key={g.id} className="flex flex-wrap items-center gap-2 rounded-xl bg-slate-50 px-3 py-2.5">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-bold text-slate-800">{g.title}</div>
                <div className="text-[11px] text-slate-500">
                  {g.weight}% wt · {g.achieved}/{g.target} {g.unit ?? ""}
                </div>
              </div>
              {achievedEditable && (
                <form
                  className="flex items-center gap-1.5"
                  onSubmit={(e) => {
                    e.preventDefault();
                    const fd = new FormData(e.currentTarget);
                    run(() => updateAchievedAction(g.id, Number(fd.get("achieved"))));
                  }}
                >
                  <input
                    name="achieved"
                    type="number"
                    step="0.5"
                    min="0"
                    defaultValue={g.achieved}
                    className="w-20 rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-xs font-semibold outline-none focus:border-emerald-400"
                  />
                  <button disabled={busy} className="rounded-lg bg-white px-2 py-1.5 text-[11px] font-bold text-emerald-600 ring-1 ring-emerald-200 active:scale-95 disabled:opacity-50">
                    Save
                  </button>
                </form>
              )}
              {editable && (
                <button
                  onClick={() => run(() => removeGoalAction(g.id))}
                  disabled={busy}
                  className="rounded-lg px-2 py-1.5 text-[11px] font-bold text-rose-500 hover:bg-rose-50 active:scale-95 disabled:opacity-50"
                >
                  ✕
                </button>
              )}
            </div>
          ))}

          {editable && (
            <div className="rounded-xl border border-dashed border-emerald-300/70 bg-emerald-50/40 p-3">
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-[1fr_64px_64px_76px]">
                <input ref={titleRef} placeholder="Goal title (e.g. Dispatch accuracy)" className="rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-xs outline-none focus:border-emerald-400" />
                <input ref={weightRef} placeholder="Wt %" type="number" min="1" max="100" className="rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-xs outline-none focus:border-emerald-400" />
                <input ref={targetRef} placeholder="Target" type="number" min="0" step="0.5" className="rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-xs outline-none focus:border-emerald-400" />
                <input ref={unitRef} placeholder="Unit" className="rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-xs outline-none focus:border-emerald-400" />
              </div>
              <button
                onClick={addGoal}
                disabled={busy}
                className="mt-2 rounded-lg bg-[#0a1628] px-3.5 py-2 text-xs font-bold text-white active:scale-95 disabled:opacity-50"
              >
                ＋ Add goal
              </button>
            </div>
          )}
          {cycleStatus === "CLOSED" && (
            <p className="rounded-lg bg-slate-50 px-3 py-2 text-[11px] font-medium text-slate-500">🔒 This cycle is locked — read-only.</p>
          )}
        </div>
      )}
    </div>
  );
}
