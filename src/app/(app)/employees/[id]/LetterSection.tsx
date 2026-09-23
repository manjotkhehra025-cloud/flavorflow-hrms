"use client";
import { Tt, useT } from "@/components/LangCtx";

import Link from "next/link";
import { useActionState, useState } from "react";
import { createLetterAction, deleteLetterAction } from "@/actions/letters";
import { addKycDocAction, deleteKycDocAction } from "@/actions/kyc";
import type { ActionState } from "@/actions/auth";
import { inputCls, btnGhost } from "@/components/ui";
import { Icon } from "@/components/icons";

type Letter = { id: string; serial: string; type: string; issuedTo: string | null; createdAt: string };
type KycDocRow = { id: string; docType: string; refNumber: string; createdAt: string };

const TYPE_LABEL: Record<string, string> = {
  EXPERIENCE: "Experience Certificate",
  JOINING: "Joining / Appointment Letter",
  KYC: "KYC / Employment Verification",
  DUTY: "Duty & Shift Pass",
};

export function LetterSection({ employeeId, letters, kycDocs, canEdit }: { employeeId: string; letters: Letter[]; kycDocs: KycDocRow[]; canEdit: boolean }) {
  const ph = useT();
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createLetterAction, {});
  const [kState, kycAction, kPending] = useActionState<ActionState, FormData>(addKycDocAction, {});
  const [, delAction] = useActionState<ActionState, FormData>(deleteKycDocAction, {});
  const [open, setOpen] = useState(false);

  return (
    <div className="mt-6 border-t border-slate-100 pt-4">
      <div className="mb-3 flex items-center justify-between">
        <h4 className="text-xs font-bold uppercase tracking-wide text-slate-500">{<Tt>Letters & Documents</Tt>}</h4>
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
            <option value="EXPERIENCE">{<Tt>Experience Certificate</Tt>}</option>
            <option value="JOINING">{<Tt>Joining / Appointment Letter</Tt>}</option>
            <option value="KYC">{<Tt>KYC / Employment Verification</Tt>}</option>
            <option value="DUTY">{<Tt>Duty & Shift Pass</Tt>}</option>
          </select>
          <input name="issuedTo" className={inputCls} placeholder={ph("Issued to (bank/authority) — optional")} />
          <button disabled={pending} className="btn-brand w-full justify-center">
            {pending ? "Creating…" : "Generate letter (auto GDF/HR serial)"}
          </button>
        </form>
      )}

      {/* KYC document locker */}
      <div className="mb-4 rounded-2xl border border-slate-200 bg-slate-50/60 p-3.5">
        <div className="mb-2 flex items-center justify-between">
          <h5 className="text-[11px] font-bold uppercase tracking-wide text-slate-500">{<Tt>KYC Document Locker</Tt>}</h5>
          <span className="text-[10px] font-semibold text-slate-400">{kycDocs.length} <Tt>docs</Tt></span>
        </div>
        {kycDocs.length > 0 && (
          <ul className="mb-2 space-y-1.5">
            {kycDocs.map((d) => (
              <li key={d.id} className="flex items-center gap-2 rounded-xl bg-white px-2.5 py-1.5 ring-1 ring-slate-100">
                <span className="rounded-md bg-[#0a1628] px-1.5 py-0.5 text-[9px] font-extrabold text-emerald-300">{d.docType}</span>
                <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-slate-600">{d.refNumber}</span>
                <span className="rounded-full bg-emerald-100 px-1.5 py-0.5 text-[9px] font-extrabold text-emerald-700">✔ Verified</span>
                {canEdit && (
                  <form action={delAction}>
                    <input type="hidden" name="kycDocId" value={d.id} />
                    <button className="rounded-lg p-1 text-slate-300 hover:bg-rose-50 hover:text-rose-500" aria-label="Delete doc">
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-3.5 w-3.5"><path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2m2 0v14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V6" strokeLinecap="round" /></svg>
                    </button>
                  </form>
                )}
              </li>
            ))}
          </ul>
        )}
        {canEdit && (
          <form action={kycAction} className="flex flex-wrap items-center gap-1.5">
            <input type="hidden" name="employeeId" value={employeeId} />
            <select name="docType" aria-label="Doc type" className="rounded-lg bg-white px-2 py-1.5 text-[11px] ring-1 ring-inset ring-slate-200">
              <option value="AADHAAR">Aadhaar</option><option value="PAN">PAN</option><option value="BANK">Bank A/c</option>
              <option value="ESIC">ESIC</option><option value="MEDICAL">Medical</option><option value="OTHER">Other</option>
            </select>
            <input name="refNumber" placeholder="Doc number…" required minLength={4} className="min-w-0 flex-1 rounded-lg bg-white px-2.5 py-1.5 text-[11px] ring-1 ring-inset ring-slate-200" />
            <button disabled={kPending} className="rounded-lg bg-emerald-500 px-2.5 py-1.5 text-[11px] font-extrabold text-white shadow disabled:opacity-50">+ <Tt>Add</Tt></button>
          </form>
        )}
        {kState.error && <p className="mt-1.5 text-[11px] text-red-600">{kState.error}</p>}
        {kState.success && <p className="mt-1.5 text-[11px] text-emerald-700">{kState.success}</p>}
      </div>

      {letters.length === 0 ? (
        <p className="rounded-xl bg-slate-50 px-3.5 py-4 text-center text-xs text-slate-400">{<Tt>No letters issued yet</Tt>}</p>
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
