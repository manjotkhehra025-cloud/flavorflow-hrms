"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState, useState } from "react";
import { editDesignationAction } from "@/actions/departments";
import type { ActionState } from "@/actions/auth";
import { inputCls } from "@/components/ui";

export function DesignationEditor({ id, title, category, departments }: {
  id: string; title: string; category: string;
  departments: { id: string; name: string }[];
}) {
  const [open, setOpen] = useState(false);
  const [state, formAction, pending] = useActionState<ActionState, FormData>(editDesignationAction, {});
  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="rounded-lg px-2.5 py-1.5 text-xs font-semibold text-emerald-600 hover:bg-emerald-50">
        <Tt>Edit</Tt>
      </button>
    );
  }
  return (
    <form action={async (fd) => { await formAction(fd); }} className="absolute right-2 top-full z-10 mt-1 min-w-56 rounded-xl border border-slate-200 bg-white p-3 shadow-xl">
      <input type="hidden" name="id" value={id} />
      <input name="title" defaultValue={title} required className={inputCls + " mb-2"} />
      <select name="category" defaultValue={category} className={inputCls + " mb-2"}>
        <option value="OFFICIAL">Official</option>
        <option value="YELLOW_CARD">Yellow Card</option>
        <option value="BOTH">Both</option>
      </select>
      <select name="departmentId" defaultValue="" className={inputCls + " mb-2"}>
        <option value="">No home dept</option>
        {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
      </select>
      <div className="flex items-center justify-between gap-2">
        <button disabled={pending} className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-extrabold text-white disabled:opacity-50">{pending ? "…" : <Tt>Save</Tt>}</button>
        <button type="button" onClick={() => setOpen(false)} className="rounded-lg px-3 py-1.5 text-xs font-semibold text-slate-500 hover:bg-slate-100"><Tt>Cancel</Tt></button>
      </div>
      {(state.error || state.success) && <p className={`mt-2 text-[11px] ${state.error ? "text-red-600" : "text-emerald-700"}`}>{state.error ?? state.success}</p>}
    </form>
  );
}
