"use client";

import { useState, useTransition, useRef } from "react";
import { useRouter } from "next/navigation";
import { createTicketAction } from "@/actions/helpdesk";

const CATS = [
  { v: "MACHINE", emoji: "🔧", label: "Machine" },
  { v: "SALARY", emoji: "💰", label: "Salary" },
  { v: "UNIFORM", emoji: "👕", label: "Uniform" },
  { v: "CANTEEN", emoji: "🍽️", label: "Canteen" },
  { v: "SAFETY", emoji: "🦺", label: "Safety" },
  { v: "OTHER", emoji: "＋", label: "Other" },
] as const;

export function RaiseTicketForm() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [cat, setCat] = useState<string>("MACHINE");
  const subjectRef = useRef<HTMLInputElement>(null);
  const bodyRef = useRef<HTMLTextAreaElement>(null);
  const [msg, setMsg] = useState<{ ok?: boolean; text: string } | null>(null);
  const [pending, startTransition] = useTransition();

  function submit() {
    const subject = subjectRef.current?.value ?? "";
    const body = bodyRef.current?.value ?? "";
    setMsg(null);
    startTransition(async () => {
      const res = await createTicketAction(cat, subject, body);
      if (res?.error) setMsg({ text: res.error });
      else {
        setMsg({ ok: true, text: res?.success ?? "Done ✓" });
        setOpen(false);
        if (subjectRef.current) subjectRef.current.value = "";
        if (bodyRef.current) bodyRef.current.value = "";
        router.refresh();
      }
    });
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="flex w-full items-center justify-center gap-2 rounded-2xl bg-gradient-to-r from-emerald-500 to-emerald-600 py-3.5 text-sm font-bold text-white shadow-[0_10px_30px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-[0.98]"
      >
        ＋ New ticket — complaint or suggestion
      </button>
    );
  }

  return (
    <div className="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-200/60">
      <div className="mb-3 flex items-center justify-between">
        <p className="text-sm font-bold text-slate-800">New ticket ✍️</p>
        <button onClick={() => setOpen(false)} className="text-xs font-semibold text-slate-400 hover:text-slate-600">Cancel ✕</button>
      </div>

      <div className="mb-3 flex flex-wrap gap-1.5">
        {CATS.map((c) => (
          <button
            key={c.v}
            onClick={() => setCat(c.v)}
            className={`flex items-center gap-1 rounded-full border px-3 py-1.5 text-xs font-bold transition active:scale-95 ${
              cat === c.v ? "border-emerald-400 bg-emerald-50 text-emerald-700" : "border-slate-200 bg-white text-slate-500 hover:bg-slate-50"
            }`}
          >
            {c.emoji} {c.label}
          </button>
        ))}
      </div>

      <input
        ref={subjectRef}
        placeholder="Subject — one short line (e.g. Mixer #2 vibration loud)"
        className="mb-2 w-full rounded-xl border border-slate-200 px-3.5 py-2.5 text-sm outline-none focus:border-emerald-400 focus:ring-2 focus:ring-emerald-100"
      />
      <textarea
        ref={bodyRef}
        rows={3}
        placeholder="Add details — what, where, since when…"
        className="mb-3 w-full rounded-xl border border-slate-200 px-3.5 py-2.5 text-sm outline-none focus:border-emerald-400 focus:ring-2 focus:ring-emerald-100"
      />

      {msg && !msg.ok && <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-xs font-medium text-red-600">{msg.text}</p>}

      <button
        onClick={submit}
        disabled={pending}
        className="w-full rounded-xl bg-[#0a1628] py-3 text-sm font-bold text-white transition active:scale-[0.98] disabled:opacity-50"
      >
        {pending ? "Sending…" : "📨 Send to HR"}
      </button>
    </div>
  );
}
