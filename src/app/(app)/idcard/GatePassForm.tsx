"use client";

import { useActionState } from "react";
import { createGatePassAction } from "@/actions/requests";
import type { ActionState } from "@/actions/auth";
import { Card, Badge, inputCls, btnBrand } from "@/components/ui";
import { Icon } from "@/components/icons";

type Pass = { id: string; date: string; exitAt: string; returnAt: string | null; reason: string | null; status: string; verified: boolean };

export function GatePassForm({ isOwner, passes }: { isOwner: boolean; passes: Pass[] }) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createGatePassAction, {});

  return (
    <Card className="p-5">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-sm font-bold text-slate-900">Digital Gate Passes</h3>
          <p className="text-xs text-slate-500">Exit permissions &amp; factory duty passes</p>
        </div>
        <span className="rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-bold text-emerald-700">({passes.length})</span>
      </div>

      {isOwner && (
        <form action={formAction} className="mb-4 rounded-2xl border border-dashed border-emerald-300 bg-emerald-50/40 p-4">
          {state.error && <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>}
          {state.success && <p className="mb-3 rounded-lg bg-emerald-100 px-3 py-2 text-sm text-emerald-800">{state.success}</p>}
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <input type="date" name="date" className={inputCls} required />
            <input type="time" name="exitAt" className={inputCls} required title="Exit time" />
            <input type="time" name="returnAt" className={inputCls} title="Return time (optional)" />
            <input type="text" name="reason" className={inputCls} placeholder="Reason (e.g. urgent work at home)" />
          </div>
          <button disabled={pending} className={`${btnBrand} mt-3`}>
            <Icon name="gate" className="h-4 w-4" /> {pending ? "Requesting…" : "+ Request Gate Pass"}
          </button>
        </form>
      )}

      {passes.length === 0 ? (
        <p className="rounded-xl bg-slate-50 px-4 py-6 text-center text-sm text-slate-400">No gate passes yet</p>
      ) : (
        <ul className="space-y-2.5">
          {passes.map((g) => (
            <li key={g.id} className="rounded-xl bg-slate-50 p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="flex items-center gap-2 text-sm font-bold text-slate-800">
                  <Icon name="gate" className="h-4 w-4 text-slate-400" /> Personal Gate Pass
                </span>
                <Badge tone={g.status === "APPROVED" ? "green" : g.status === "REJECTED" ? "red" : "amber"}>{g.status}</Badge>
              </div>
              <p className="mt-1 text-xs text-slate-500">
                Exit: {g.exitAt}{g.returnAt ? ` | Return: ${g.returnAt}` : ""} · {g.date}
                {g.reason ? ` • "${g.reason}"` : ""}
              </p>
              {g.verified && (
                <div className="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-emerald-100 px-2.5 py-1 text-[11px] font-black text-emerald-700">
                  ✓ ENTRY VERIFIED
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
