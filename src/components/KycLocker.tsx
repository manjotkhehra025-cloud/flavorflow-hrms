"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState } from "react";
import { addKycDocAction, deleteKycDocAction } from "@/actions/kyc";
import type { ActionState } from "@/actions/auth";

type Doc = { id: string; docType: string; refNumber: string };

/** Employee's own KYC document locker — add & remove document numbers. */
export function KycLocker({ docs }: { docs: Doc[] }) {
  const [addState, addAction, addPending] = useActionState<ActionState, FormData>(addKycDocAction, {});
  const [, delAction] = useActionState<ActionState, FormData>(deleteKycDocAction, {});
  return (
    <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
      <header className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-4 py-2.5">
        <h3 className="text-sm font-extrabold text-slate-800"><Tt>My Document Locker</Tt></h3>
        <span className="text-[10px] font-semibold text-slate-400">{docs.length} <Tt>saved</Tt></span>
      </header>
      <div className="p-4">
        {docs.length > 0 ? (
          <ul className="mb-3 space-y-1.5">
            {docs.map((d) => (
              <li key={d.id} className="flex items-center gap-2 rounded-xl bg-slate-50 px-3 py-2">
                <span className="rounded-md bg-[#0a1628] px-1.5 py-0.5 text-[9px] font-extrabold text-emerald-300">{d.docType}</span>
                <span className="min-w-0 flex-1 truncate font-mono text-xs text-slate-600">{d.refNumber}</span>
                <form action={delAction}>
                  <input type="hidden" name="kycDocId" value={d.id} />
                  <button aria-label="Delete" className="rounded-lg p-1 text-slate-300 hover:bg-rose-50 hover:text-rose-500">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-3.5 w-3.5"><path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2m2 0v14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V6" strokeLinecap="round" /></svg>
                  </button>
                </form>
              </li>
            ))}
          </ul>
        ) : (
          <p className="mb-3 text-xs text-slate-400"><Tt>Keep your Aadhaar / PAN / bank details handy — HR uses these for KYC letters.</Tt></p>
        )}
        <form action={addAction} className="flex flex-wrap items-center gap-1.5">
          <select name="docType" aria-label="Doc type" className="rounded-lg bg-slate-50 px-2 py-2 text-xs ring-1 ring-inset ring-slate-200">
            <option value="AADHAAR">Aadhaar</option><option value="PAN">PAN</option><option value="BANK">Bank A/c</option>
            <option value="ESIC">ESIC</option><option value="MEDICAL">Medical</option><option value="OTHER">Other</option>
          </select>
          <input name="refNumber" placeholder="Document number…" required minLength={4} className="min-w-0 flex-1 rounded-lg bg-slate-50 px-3 py-2 text-xs outline-none ring-1 ring-inset ring-slate-200 focus:ring-2 focus:ring-emerald-400" />
          <button disabled={addPending} className="rounded-lg bg-emerald-500 px-3 py-2 text-xs font-extrabold text-white shadow disabled:opacity-50">+ <Tt>Add</Tt></button>
        </form>
        {(addState.error || addState.success) && (
          <p className={`mt-2 text-xs font-semibold ${addState.error ? "text-red-600" : "text-emerald-700"}`}>{addState.error ?? addState.success}</p>
        )}
      </div>
    </div>
  );
}
