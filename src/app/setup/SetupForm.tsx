"use client";

import { useActionState } from "react";
import { setupAction } from "@/actions/setup";
import type { ActionState } from "@/actions/auth";

const input =
  "w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-200";

export function SetupForm() {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(setupAction, {});

  return (
    <form action={formAction} className="space-y-4">
      {state.error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>
      )}
      <div className="grid grid-cols-3 gap-3">
        <div className="col-span-2">
          <label className="mb-1 block text-sm font-medium text-slate-700">Company name</label>
          <input name="companyName" required className={input} placeholder="FlavorFlow Foods Pvt. Ltd." />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Code</label>
          <input name="companyCode" required maxLength={6} className={input} placeholder="FF" />
        </div>
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Your name (Admin)</label>
        <input name="name" required className={input} placeholder="Full name" />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Work email</label>
        <input name="email" type="email" required className={input} placeholder="admin@flavorflow.co.in" />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">Password (min 8 chars)</label>
        <input name="password" type="password" required minLength={8} className={input} />
      </div>
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-lg bg-amber-500 px-4 py-2.5 text-sm font-semibold text-slate-950 hover:bg-amber-400 disabled:opacity-50"
      >
        {pending ? "Creating workspace…" : "Create workspace"}
      </button>
    </form>
  );
}
