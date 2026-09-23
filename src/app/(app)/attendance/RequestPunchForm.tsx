"use client";
import { Tt, useT } from "@/components/LangCtx";

import { useActionState } from "react";
import { createPunchRequestAction } from "@/actions/requests";
import type { ActionState } from "@/actions/auth";
import { Card, Badge, inputCls, btnBrand } from "@/components/ui";
import { Icon } from "@/components/icons";
import { fmtDate } from "@/lib/utils";

type Req = { id: string; type: string; date: Date; time: string | null; hours: number | null; status: string };

export function RequestPunchForm({ recent, otApprovedHours = 0 }: { recent: Req[]; otApprovedHours?: number }) {
  const ph = useT();
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createPunchRequestAction, {});

  return (
    <Card className="mb-6 p-5">
      <h3 className="text-sm font-bold text-slate-900">{<Tt>Manual Punch / OT Request</Tt>}</h3>
      <p className="mb-4 text-xs text-slate-500">Missed a punch? Or overtime? Your manager will review & approve it.</p>

      {state.error && <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>}
      {state.success && <p className="mb-3 rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700">{state.success}</p>}

      <form action={formAction} className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <select name="type" className={inputCls} defaultValue="MANUAL_IN" required>
          <option value="MANUAL_IN">{<Tt>Manual Punch In</Tt>}</option>
          <option value="MANUAL_OUT">{<Tt>Manual Punch Out</Tt>}</option>
          <option value="OT">{<Tt>Overtime (OT)</Tt>}{otApprovedHours > 0 ? ` · ${otApprovedHours}h approved` : ""}</option>
        </select>
        <input type="date" name="date" className={inputCls} required />
        <input type="time" name="time" className={inputCls} placeholder={ph("Time")} />
        <input type="number" name="hours" step="0.5" min="0" max="12" className={inputCls} placeholder={ph("OT hours")} />
        <input type="text" name="reason" className={inputCls + " sm:col-span-2 lg:col-span-1"} placeholder={ph("Reason *")} required />
        <button disabled={pending} className={btnBrand}>
          <Icon name="plus" className="h-4 w-4" />{pending ? "Sending…" : "Request"}
        </button>
      </form>

      {recent.length > 0 && (
        <div className="mt-4 space-y-1.5">
          {recent.slice(0, 4).map((r) => (
            <div key={r.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-slate-50 px-3.5 py-2 text-xs">
              <span className="font-semibold text-slate-700">
                <Icon name="clock" className="mr-1 inline h-3.5 w-3.5 text-slate-400" />
                {r.type === "OT" ? `OT ${r.hours}h` : r.type === "MANUAL_IN" ? "Punch In" : "Punch Out"} · {fmtDate(r.date)}
                {r.time ? ` at ${r.time}` : ""}
              </span>
              <Badge tone={r.status === "APPROVED" ? "green" : r.status === "REJECTED" ? "red" : "amber"}>{r.status}</Badge>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
