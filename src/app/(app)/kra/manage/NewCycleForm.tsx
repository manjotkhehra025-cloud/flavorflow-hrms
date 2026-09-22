"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createCycleAction } from "@/actions/kra";

const QUARTERS = [1, 2, 3, 4] as const;

export function NewCycleForm() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [quarter, setQuarter] = useState(Math.floor(now.getMonth() / 3) + 1);
  const [msg, setMsg] = useState<{ ok?: boolean; text: string } | null>(null);
  const [pending, startTransition] = useTransition();

  function create() {
    setMsg(null);
    startTransition(async () => {
      const res = await createCycleAction(year, quarter);
      if (res?.error) setMsg({ text: res.error });
      else {
        setMsg({ ok: true, text: res?.success ?? "Created ✓" });
        setOpen(false);
        router.refresh();
      }
    });
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="rounded-xl bg-gradient-to-r from-emerald-500 to-emerald-600 px-3.5 py-2 text-xs font-bold text-white shadow-[0_8px_20px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-95"
      >
        ＋ New cycle
      </button>
    );
  }

  return (
    <div className="w-full rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-200/60">
      <p className="mb-3 text-xs font-bold text-slate-700">Nava KRA cycle — year te quarter chuno</p>
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={year}
          onChange={(e) => setYear(Number(e.target.value))}
          className="rounded-lg border border-slate-200 px-2.5 py-2 text-xs font-semibold outline-none focus:border-emerald-400"
        >
          {[now.getFullYear() - 1, now.getFullYear(), now.getFullYear() + 1].map((y) => (
            <option key={y} value={y}>{y}</option>
          ))}
        </select>
        {QUARTERS.map((q) => (
          <button
            key={q}
            onClick={() => setQuarter(q)}
            className={`rounded-lg px-3 py-2 text-xs font-bold transition ${
              quarter === q ? "bg-[#0a1628] text-white" : "bg-slate-100 text-slate-600 hover:bg-slate-200"
            }`}
          >
            Q{q}
          </button>
        ))}
        <button
          onClick={create}
          disabled={pending}
          className="rounded-lg bg-gradient-to-r from-emerald-500 to-emerald-600 px-4 py-2 text-xs font-bold text-white active:scale-95 disabled:opacity-50"
        >
          {pending ? "…" : "Create cycle"}
        </button>
        <button onClick={() => setOpen(false)} className="px-2 py-2 text-xs font-semibold text-slate-400 hover:text-slate-600">
          Cancel
        </button>
      </div>
      {msg && (
        <p className={`mt-2 rounded-lg px-3 py-2 text-xs font-medium ${msg.ok ? "bg-emerald-50 text-emerald-700" : "bg-red-50 text-red-600"}`}>
          {msg.text}
        </p>
      )}
    </div>
  );
}
