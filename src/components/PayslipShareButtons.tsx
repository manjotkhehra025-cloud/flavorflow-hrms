"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState } from "react";
import { createPayslipLinkAction } from "@/actions/payroll";
import type { ActionState } from "@/actions/auth";

const btn = "inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-[11px] font-bold text-slate-700 transition hover:border-emerald-400 hover:text-emerald-700";

export function PayslipShareButtons({ rowId }: { rowId: string }) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createPayslipLinkAction, {});
  const token = state.success;

  function copy() {
    if (!token) return;
    const url = location.origin + token;
    navigator.clipboard?.writeText(url).catch(() => {});
  }

  return (
    <span className="inline-flex items-center gap-1.5">
      {!token && (
        <form action={formAction}>
          <input type="hidden" name="rowId" value={rowId} />
          <button type="submit" className={btn} disabled={pending}>
            {pending ? "…" : <><Tt>Share link</Tt></>}
          </button>
        </form>
      )}
      {token && (
        <>
          <a
            href={"https://wa.me/?text=" + encodeURIComponent(location.origin + token)}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-3 py-1.5 text-[11px] font-black text-white transition hover:bg-emerald-700"
          >
            <Tt>WhatsApp</Tt>
          </a>
          <button type="button" onClick={copy} className={btn}>🔗 <Tt>Copy</Tt></button>
        </>
      )}
      {state.error && <span className="text-[10px] text-rose-600">{state.error}</span>}
    </span>
  );
}
