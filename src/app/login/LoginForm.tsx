"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState } from "react";
import { loginAction, type ActionState } from "@/actions/auth";

export function LoginForm() {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(loginAction, {});

  return (
    <form action={formAction} className="space-y-4">
      {state.error && (
        <p className="rounded-xl bg-red-50 px-3.5 py-2.5 text-sm font-medium text-red-600 ring-1 ring-inset ring-red-600/20">
          {state.error}
        </p>
      )}
      <div>
        <label className="mb-1.5 block text-sm font-semibold text-slate-700">{<Tt>Email</Tt>}</label>
        <input
          name="email"
          type="email"
          required
          autoComplete="email"
          placeholder="you@gdfoods.co.in"
          className="input"
        />
      </div>
      <div>
        <label className="mb-1.5 block text-sm font-semibold text-slate-700">{<Tt>Password</Tt>}</label>
        <input
          name="password"
          type="password"
          required
          autoComplete="current-password"
          placeholder="••••••••"
          className="input"
        />
      </div>
      <button type="submit" disabled={pending} className="btn-brand w-full">
        {pending ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
