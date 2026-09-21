"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { createLetterAction, deleteLetterAction } from "@/actions/letters";
import type { ActionState } from "@/actions/auth";
import { inputCls, btnGhost } from "@/components/ui";
import { Icon } from "@/components/icons";

type Letter = { id: string; serial: string; type: string; issuedTo: string | null; createdAt: string };

const TYPE_LABEL: Record<string, string> = {
  EXPERIENCE: "Experience Certificate",
  JOINING: "Joining / Appointment Letter",
  KYC: "KYC / Employment Verification",
};

export function LetterSection({ employeeId, letters }: { employeeId: string; letters: Letter[] }) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createLetterAction, {});
  const [open, setOpen] = useState(false);

  return (
    <div className="mt-6 border-t border-slate-100 pt-4">
      <div className="mb-3 flex items-center justify-between">
        <h4 className="text-xs font-bold uppercase tracking-wide text-slate-500">Letters & Documents</h4>
        <button onClick={() => setOpen(!open)} className="text-[11px] font-semibold text-emerald-600 hover:underline">
          {open ? "Hide" : "+ Generate"}
        </button>
      </div>

      {open && (
        <form action={formAction} className="mb-4 space-y-2.5 rounded-2xl border border-emerald-200 bg-emerald-50/40 p-3.5">
          {state.error && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{state.error}</p>}
          {state.success && <p className="rounded-lg bg-emerald-100 px-3 py-2 text-xs text-emerald-800">{state.success}</p>}
          <input type="hidden" name="employeeId" value={employeeId} />
          <select name="type" className={inputCls} required>
            <option value="EXPERIENCE">Experience Certificate</option>
            <option value="JOINING">Joining / Appointment Letter</option>
            <option value="KYC">KYC / Employment Verification</option>
          </select>
          <input name="issuedTo" className={inputCls} placeholder="Issued to (bank/authority) — optional" />
          <button disabled={pending} className="btn-brand w-full justify-center">
            {pending ? "Creating…" : "Generate letter (auto GDF/HR serial)"}
          </button>
        </form>
      )}

      {letters.length === 0 ? (
        <p className="rounded-xl bg-slate-50 px-3.5 py-4 text-center text-xs text-slate-400">Koi letter issue nahi hoya abhi tak</p>
      ) : (
        <ul className="space-y-1.5">
          {letters.map((l) => (
            <li key={l.id} className="flex items-center justify-between gap-2 rounded-xl bg-slate-50 px-3.5 py-2.5">
              <div className="min-w-0">
                <div className="truncate text-xs font-bold text-slate-800">{l.serial}</div>
                <div className="text-[11px] text-slate-500">
                  {TYPE_LABEL[l.type] ?? l.type}
                  {l.issuedTo ? ` → ${l.issuedTo}` : ""} · {new Date(l.createdAt).toLocaleDateString("en-IN")}
                </div>
              </div>
              <div className="flex shrink-0 gap-1">
                <Link href={`/letters/${l.id}`} target="_blank" className="rounded-lg bg-emerald-500/10 px-2.5 py-1.5 text-[11px] font-bold text-emerald-700 hover:bg-emerald-500/20">
                  View
                </Link>
                <form action={() => deleteLetterAction(l.id)}>
                  <button className="rounded-lg px-2 py-1.5 text-[11px] font-bold text-red-400 hover:bg-red-50">✕</button>
                </form>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
