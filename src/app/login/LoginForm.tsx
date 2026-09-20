"use client";

import { useActionState } from "react";
import { loginAction, type ActionState } from "@/actions/auth";

export function LoginForm() {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(loginAction, {});

  return (
    <form action={formAction} className="space-y-4">
      {state.error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>
      )}
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Email</label>
        <input
          name="email"
          type="email"
          required
          autoComplete="email"
          placeholder="you@flavorflow.co.in"
          className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-200"
        />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Password</label>
        <input
          name="password"
          type="password"
          required
          autoComplete="current-password"
          className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-200"
        />
      </div>
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-lg bg-slate-950 px-4 py-2.5 text-sm font-semibold text-white hover:bg-slate-800 disabled:opacity-50"
      >
        {pending ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
