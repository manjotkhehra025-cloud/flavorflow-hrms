"use client";

import { useActionState } from "react";
import { setInitialPasswordAction } from "@/actions/auth";
import type { ActionState } from "@/actions/auth";
import { Tt, useT } from "@/components/LangCtx";

const inputCls =
  "w-full rounded-xl border-0 bg-white px-4 py-3 text-sm text-slate-900 ring-1 ring-slate-200 placeholder:text-slate-400 focus:ring-2 focus:ring-emerald-500";

export function SetPasswordForm() {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(setInitialPasswordAction, {});
  const t = useT();
  return (
    <form action={formAction} className="space-y-3">
      <input
        type="password"
        name="newPassword"
        required
        minLength={6}
        autoComplete="new-password"
        placeholder={t("Choose your new password (only you know it)")}
        className={inputCls}
      />
      <input
        type="password"
        name="confirmPassword"
        required
        minLength={6}
        autoComplete="new-password"
        placeholder={t("Type the same password again")}
        className={inputCls}
      />
      {state.error && <p className="text-xs font-semibold text-red-600">{state.error}</p>}
      <button
        disabled={pending}
        className="w-full rounded-xl bg-[#0a1628] py-3 text-sm font-extrabold text-emerald-300 shadow transition active:scale-[0.99] disabled:opacity-60"
      >
        {pending ? <Tt>Saving…</Tt> : <Tt>Save my password & log in →</Tt>}
      </button>
      <p className="text-center text-[11px] leading-relaxed text-slate-400">
        <Tt>After saving you'll be signed out — log in again with this new password to open your dashboard.</Tt>
      </p>
    </form>
  );
}
