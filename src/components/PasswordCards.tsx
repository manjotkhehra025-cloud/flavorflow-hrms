"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState, useState, useTransition } from "react";
import { changePasswordAction, adminResetPasswordAction } from "@/actions/auth";
import type { ActionState } from "@/actions/auth";
import { inputCls } from "@/components/ui";

/** Change-my-password card — shown to every signed-in user on Settings. */
export function ChangePasswordCard() {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(changePasswordAction, {});
  return (
    <div className="mb-6 rounded-3xl border border-slate-200 bg-white p-5 shadow-sm">
      <h3 className="text-sm font-bold text-slate-900"><Tt>Change my PIN / password</Tt></h3>
      <p className="mt-0.5 text-xs text-slate-500"><Tt>Same login works on the phone app. Minimum 6 characters.</Tt></p>
      <form action={formAction} className="mt-3 flex flex-wrap items-end gap-2.5">
        <label>
          <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Current</Tt></span>
          <input type="password" name="current" required className={inputCls} autoComplete="current-password" />
        </label>
        <label>
          <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>New</Tt></span>
          <input type="password" name="next" required minLength={6} className={inputCls} autoComplete="new-password" />
        </label>
        <button disabled={pending} className="btn-brand !py-2 text-xs">{pending ? "…" : <Tt>Change ✔</Tt>}</button>
        {(state.error || state.success) && (
          <p className={`w-full text-xs font-semibold ${state.error ? "text-red-600" : "text-emerald-700"}`}>{state.error ?? state.success}</p>
        )}
      </form>
    </div>
  );
}

/** Staff touch: reset an employee's login — shows the temp password ONCE. */
export function AdminResetButton({ userId, name, compact = false }: { userId: string; name: string; compact?: boolean }) {
  const [temp, setTemp] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  if (compact) {
    // Tiny inline lock-reset for the employees table — password appears inside a small popover note.
    return (
      <span className="relative inline-flex items-center">
        <button
          type="button"
          title="Reset password"
          disabled={pending}
          onClick={() =>
            startTransition(async () => {
              if (!confirm(`Reset ${name.split(" ")[0]}'s password? Their old login will stop working immediately.`)) return;
              const fd = new FormData();
              fd.set("userId", userId);
              const res = await adminResetPasswordAction(fd);
              if (res.temp) { setTemp(res.temp); setErr(null); } else { setErr(res.error ?? "Failed"); }
            })
          }
          className="flex h-5 w-5 items-center justify-center rounded-full bg-amber-50 text-[10px] font-black text-amber-700 ring-1 ring-amber-200 transition hover:bg-amber-100 disabled:opacity-50"
        >
          {pending ? "…" : "⟳"}
        </button>
        {temp && (
          <span className="absolute bottom-6 left-0 z-10 w-56 rounded-xl bg-emerald-600 px-3 py-2 text-[11px] font-bold text-white shadow-lg">
            Temp password: <span className="font-mono tracking-wider">{temp}</span>
          </span>
        )}
      </span>
    );
  }
  return (
    <div className="mt-2">
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            const fd = new FormData();
            fd.set("userId", userId);
            const res = await adminResetPasswordAction(fd);
            if (res.temp) { setTemp(res.temp); setErr(null); } else { setErr(res.error ?? "Failed"); }
          })
        }
        className="rounded-xl bg-amber-50 px-3 py-1.5 text-xs font-bold text-amber-700 ring-1 ring-amber-200 transition hover:bg-amber-100 disabled:opacity-50"
      >
        {pending ? "…" : `Reset ${name.split(" ")[0]}'s password`}
      </button>
      {temp && (
        <div className="mt-2 rounded-xl bg-emerald-50 px-3 py-2 text-xs ring-1 ring-emerald-200">
          <Tt>Temporary password (share once — it won't show again)</Tt>:
          <span className="ml-1.5 font-mono font-black tracking-wider text-emerald-700">{temp}</span>
        </div>
      )}
      {err && <p className="mt-2 text-xs text-red-600">{err}</p>}
    </div>
  );
}
