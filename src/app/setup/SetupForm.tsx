"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState } from "react";
import { setupAction } from "@/actions/setup";
import type { ActionState } from "@/actions/auth";

const input = "input";

export function SetupForm() {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(setupAction, {});

  return (
    <form action={formAction} className="space-y-4">
      {state.error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>
      )}
      <div className="grid grid-cols-3 gap-3">
        <div className="col-span-2">
          <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>Company name</Tt>}</label>
          <input name="companyName" required className={input} placeholder="G.D. Foods Mfg. (I) Pvt. Ltd." />
        </div>
        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>Code</Tt>}</label>
          <input name="companyCode" required maxLength={6} className={input} placeholder="FF" />
        </div>
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>Your name (Admin)</Tt>}</label>
        <input name="name" required className={input} placeholder="Full name" />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>Work email</Tt>}</label>
        <input name="email" type="email" required className={input} placeholder="admin@flavorflow.co.in" />
      </div>
      <div>
        <label className="mb-1 block text-sm font-medium text-slate-700">{<Tt>Password (min 8 chars)</Tt>}</label>
        <input name="password" type="password" required minLength={8} className={input} />
      </div>
      <button
        type="submit"
        disabled={pending}
        className="btn-brand w-full"
      >
        {pending ? "Creating workspace…" : "Create workspace"}
      </button>
    </form>
  );
}
