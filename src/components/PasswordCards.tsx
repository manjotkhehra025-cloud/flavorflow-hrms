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

/** Super admin: set a STARTING password (typed, never shown back) — the employee replaces it at first login. */
export function AdminResetButton({ userId, name, compact = false }: { userId: string; name: string; compact?: boolean }) {
  const [ok, setOk] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [pw, setPw] = useState("");
  const [pending, startTransition] = useTransition();
  const doReset = () =>
    startTransition(async () => {
      if (pw.trim().length < 6) { setErr("Min 6 characters"); return; }
      if (!confirm(`Reset ${name.split(" ")[0]}'s password? They'll log in with this starting password once, then must pick their own.`)) return;
      const fd = new FormData();
      fd.set("userId", userId);
      fd.set("newPassword", pw.trim());
      const res = await adminResetPasswordAction(fd);
      if (res.ok) { setOk(true); setErr(null); setPw(""); }
      else setErr(res.error ?? "Failed");
    });

  if (compact) {
    return (
      <span className="relative inline-flex items-center gap-1">
        <input
          type="text"
          value={pw}
          onChange={(e) => { setPw(e.target.value); setOk(false); }}
          placeholder="start pw"
          className="h-6 w-24 rounded-md bg-white px-1.5 text-[11px] ring-1 ring-slate-200 placeholder:text-slate-300 focus:ring-emerald-400"
        />
        <button
          type="button"
          title="Reset password"
          disabled={pending}
          onClick={doReset}
          className="flex h-5 w-5 items-center justify-center rounded-full bg-amber-50 text-[10px] font-black text-amber-700 ring-1 ring-amber-200 transition hover:bg-amber-100 disabled:opacity-50"
        >
          {pending ? "…" : "⟳"}
        </button>
        {ok && <span className="text-[10px] font-bold text-emerald-600">✔</span>}
        {err && <span className="absolute bottom-6 left-0 z-10 rounded-lg bg-red-600 px-2 py-1 text-[10px] font-bold text-white">{err}</span>}
      </span>
    );
  }
  return (
    <div className="mt-2">
      <div className="flex items-center gap-2">
        <input
          type="text"
          value={pw}
          onChange={(e) => { setPw(e.target.value); setOk(false); }}
          placeholder="starting password (say it verbally)"
          autoComplete="off"
          className="w-56 rounded-xl bg-white px-3 py-2 text-xs ring-1 ring-slate-200 placeholder:text-slate-300 focus:ring-2 focus:ring-emerald-500"
        />
        <button
          type="button"
          disabled={pending}
          onClick={doReset}
          className="rounded-xl bg-amber-50 px-3 py-2 text-xs font-bold text-amber-700 ring-1 ring-amber-200 transition hover:bg-amber-100 disabled:opacity-50"
        >
          {pending ? "…" : `Reset ${name.split(" ")[0]}'s password`}
        </button>
      </div>
      {ok && (
        <p className="mt-2 text-[11px] font-semibold text-emerald-700">
          <Tt>Done ✔ — they log in once with your starting password, then the app makes them choose their own before the dashboard opens.</Tt>
        </p>
      )}
      {err && <p className="mt-2 text-xs text-red-600">{err}</p>}
    </div>
  );
}
