"use client";

import { useState, useTransition, useRef } from "react";
import { useRouter } from "next/navigation";
import { replyTicketAction } from "@/actions/helpdesk";

export function ReplyBox({ ticketId }: { ticketId: string }) {
  const router = useRouter();
  const ref = useRef<HTMLInputElement>(null);
  const [err, setErr] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function send() {
    const body = ref.current?.value ?? "";
    if (!body.trim()) {
      setErr("Reply likho.");
      return;
    }
    setErr(null);
    startTransition(async () => {
      const res = await replyTicketAction(ticketId, body);
      if (res?.error) setErr(res.error);
      else {
        if (ref.current) ref.current.value = "";
        router.refresh();
      }
    });
  }

  return (
    <div className="rounded-2xl bg-white p-3 shadow-sm ring-1 ring-slate-200/60">
      {err && <p className="mb-2 rounded-lg bg-red-50 px-3 py-1.5 text-xs font-medium text-red-600">{err}</p>}
      <div className="flex items-center gap-2">
        <input
          ref={ref}
          onKeyDown={(e) => e.key === "Enter" && send()}
          placeholder="Reply likho…"
          className="flex-1 rounded-xl border border-slate-200 px-3.5 py-2.5 text-sm outline-none focus:border-emerald-400 focus:ring-2 focus:ring-emerald-100"
        />
        <button
          onClick={send}
          disabled={pending}
          className="rounded-xl bg-gradient-to-r from-emerald-500 to-emerald-600 px-5 py-2.5 text-sm font-bold text-white transition active:scale-95 disabled:opacity-50"
        >
          {pending ? "…" : "Send"}
        </button>
      </div>
    </div>
  );
}
