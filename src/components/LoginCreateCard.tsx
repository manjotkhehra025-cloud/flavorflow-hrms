"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState } from "react";
import { createLoginForEmployeeAction } from "@/actions/employees";
import type { ActionState } from "@/actions/auth";
import { inputCls } from "@/components/ui";

/** Staff: create & link a login (admin/HR can later also link from user screen). */
export function LoginCreateCard({ employeeId, name }: { employeeId: string; name: string }) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createLoginForEmployeeAction, {});
  return (
    <div className="mt-2 rounded-xl bg-slate-50 p-3">
      <p className="mb-2 text-xs font-bold text-slate-600">
        <Tt>Create login</Tt> — {name}
      </p>
      <form action={formAction} className="space-y-2">
        <input type="hidden" name="employeeId" value={employeeId} />
        <input type="email" name="email" required placeholder="login id (email)…" className={inputCls} autoComplete="off" />
        <div className="flex gap-2">
          <input name="password" required minLength={6} placeholder="temp PIN/password" className={inputCls} autoComplete="new-password" />
          <select name="role" defaultValue="EMPLOYEE" className={inputCls + " !w-28"}>
            <option value="EMPLOYEE"><Tt>Employee</Tt></option>
            <option value="HR">HR</option>
            <option value="ADMIN">ADMIN</option>
          </select>
        </div>
        <button disabled={pending} className="rounded-xl bg-[#0a1628] px-4 py-2 text-xs font-extrabold text-emerald-300 shadow disabled:opacity-50">
          {pending ? "…" : <Tt>Create & link login ✔</Tt>}
        </button>
        {(state.error || state.success) && (
          <p className={`text-xs font-semibold ${state.error ? "text-red-600" : "text-emerald-700"}`}>{state.error ?? state.success}</p>
        )}
      </form>
    </div>
  );
}
