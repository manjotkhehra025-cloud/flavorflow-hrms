"use client";
import { Tt, useT } from "@/components/LangCtx";

import { useActionState } from "react";
import { applyLeaveAction } from "@/actions/leaves";
import type { ActionState } from "@/actions/auth";
import { inputCls, btnBrand } from "@/components/ui";

type LeaveType = { id: string; name: string; daysPerYear: number };

export function ApplyLeaveForm({ leaveTypes }: { leaveTypes: LeaveType[] }) {
  const ph = useT();
  const [state, formAction, pending] = useActionState<ActionState, FormData>(applyLeaveAction, {});
  const [submitted, setSubmitted] = useStateOk();

  return (
    <form
      action={async (fd) => {
        const res = formAction(fd);
        setSubmitted();
        return res;
      }}
      className="space-y-4"
    >
      {state.error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>
      )}
      {submitted && !state.error && !pending && (
        <p className="rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
          Request submitted — your approver has been notified.
        </p>
      )}
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>Leave type</Tt>}</label>
        <select name="leaveTypeId" required className={inputCls}>
          <option value="">{<Tt>Choose…</Tt>}</option>
          {leaveTypes.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}{t.daysPerYear > 0 ? ` (${t.daysPerYear}/yr)` : ""}
            </option>
          ))}
        </select>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>From</Tt>}</label>
          <input type="date" name="fromDate" required className={inputCls} />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>To</Tt>}</label>
          <input type="date" name="toDate" required className={inputCls} />
        </div>
      </div>
      <label className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
        <input type="checkbox" name="halfDay" />
        {<Tt>Half day (0.5) — single day only, half pay</Tt>}
      </label>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>Reason (optional)</Tt>}</label>
        <textarea name="reason" rows={2} className={inputCls} placeholder={ph("Short note for your approver")} />
      </div>
      <button type="submit" disabled={pending} className={btnBrand}>
        {pending ? "Submitting…" : "Submit request"}
      </button>
    </form>
  );
}

// Small helper to show a success message after submit without extra deps.
import { useState } from "react";
function useStateOk(): [boolean, () => void] {
  const [ok, setOk] = useState(false);
  return [ok, () => setOk(true)];
}
