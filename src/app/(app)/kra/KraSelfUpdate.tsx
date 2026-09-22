"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { updateAchievedAction } from "@/actions/kra";

export function KraSelfUpdate({ goalId, achieved, unit }: { goalId: string; achieved: number; unit: string | null }) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [msg, setMsg] = useState<{ ok?: boolean; text: string } | null>(null);
  const [pending, startTransition] = useTransition();

  function save() {
    const v = Number(inputRef.current?.value);
    if (Number.isNaN(v) || v < 0) {
      setMsg({ text: "Please enter a valid number (0 or more)." });
      return;
    }
    setMsg(null);
    startTransition(async () => {
      const res = await updateAchievedAction(goalId, v);
      if (res?.error) setMsg({ text: res.error });
      else {
        setMsg({ ok: true, text: res?.success ?? "Updated ✓" });
        router.refresh();
      }
    });
  }

  return (
    <div className="mt-3 border-t border-dashed border-slate-100 pt-3">
      {msg && (
        <p className={`mb-2 rounded-lg px-2.5 py-1.5 text-[11px] font-medium ${msg.ok ? "bg-emerald-50 text-emerald-700" : "bg-red-50 text-red-600"}`}>
          {msg.text}
        </p>
      )}
      <div className="flex items-center gap-2">
        <input
          ref={inputRef}
          type="number"
          step="0.5"
          min="0"
          defaultValue={achieved}
          className="w-24 rounded-lg border border-slate-200 px-3 py-2 text-sm font-semibold outline-none focus:border-emerald-400 focus:ring-2 focus:ring-emerald-100"
        />
        <span className="text-xs text-slate-400">{unit ?? ""}</span>
        <button
          onClick={save}
          disabled={pending}
          className="ml-auto rounded-lg bg-emerald-500 px-3.5 py-2 text-xs font-bold text-white transition hover:bg-emerald-600 active:scale-95 disabled:opacity-50"
        >
          {pending ? "…" : "✎ Update"}
        </button>
      </div>
    </div>
  );
}
