"use client";
import { Tt } from "@/components/LangCtx";

import { useActionState, useState } from "react";
import { deleteShiftAction, updateShiftAction } from "@/actions/shifts";
import type { ActionState } from "@/actions/auth";
import { Icon } from "@/components/icons";
import { inputCls } from "@/components/ui";

function shiftTone(startTime: string): { label: string; emoji: string } {
  const h = parseInt(startTime.split(":")[0] ?? "9", 10);
  if (h >= 5 && h < 12) return { label: "Morning", emoji: "🌅" };
  if (h >= 12 && h < 17) return { label: "Evening", emoji: "🌇" };
  if (h >= 21 || h < 5) return { label: "Night", emoji: "🌙" };
  return { label: "Evening", emoji: "🌇" };
}

export function ShiftRow({ id, name, startTime, durationH, count }: { id: string; name: string; startTime: string; durationH: number; count: number }) {
  const [edit, setEdit] = useState(false);
  const [upState, upAction, upPending] = useActionState<ActionState, FormData>(updateShiftAction, {});
  const tone = shiftTone(startTime);

  if (edit) {
    return (
      <li className="rounded-xl bg-slate-50 px-4 py-3">
        <form action={async (fd) => { await upAction(fd); }} className="flex flex-wrap items-end gap-2">
          <input type="hidden" name="shiftId" value={id} />
          <label className="grow min-w-28">
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-wide text-slate-500"><Tt>Name</Tt></span>
            <input name="name" defaultValue={name} required className={inputCls} />
          </label>
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-wide text-slate-500"><Tt>Start</Tt></span>
            <input name="startTime" defaultValue={startTime} pattern="\\d{2}:\\d{2}" placeholder="08:00" required className={`${inputCls} w-24`} />
          </label>
          <label>
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-wide text-slate-500"><Tt>Hours</Tt></span>
            <input name="durationH" type="number" min={1} max={16} step={0.5} defaultValue={durationH} required className={`${inputCls} w-20`} />
          </label>
          <button disabled={upPending} className="btn-brand !py-2 text-xs">{upPending ? "…" : <Tt>Save ✔</Tt>}</button>
          <button type="button" onClick={() => setEdit(false)} className="rounded-xl px-3 py-2 text-xs font-bold text-slate-500 hover:bg-slate-200"><Tt>Cancel</Tt></button>
        </form>
        {(upState.error || upState.success) && (
          <p className={`mt-2 text-xs font-semibold ${upState.error ? "text-red-600" : "text-emerald-700"}`}>{upState.error ?? upState.success}</p>
        )}
      </li>
    );
  }

  return (
    <li className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-slate-50 px-4 py-3">
      <div className="flex items-center gap-3">
        <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#0a1628] text-base">{tone.emoji}</span>
        <div>
          <div className="text-sm font-bold text-slate-800">{name} <span className="ml-1 rounded-full bg-emerald-100 px-1.5 py-0.5 text-[9px] font-extrabold uppercase text-emerald-700">{<Tt>{tone.label}</Tt>}</span></div>
          <div className="text-xs text-slate-500"><Tt>Starts</Tt> {startTime} · {durationH}h · {count} <Tt>employee(s)</Tt></div>
        </div>
      </div>
      <div className="flex items-center gap-1">
        <button type="button" onClick={() => setEdit(true)} className="rounded-lg px-2.5 py-1.5 text-xs font-semibold text-emerald-600 hover:bg-emerald-50"><Tt>Edit</Tt></button>
        <form action={async (fd: FormData) => { await deleteShiftAction({}, fd); }}>
          <input type="hidden" name="id" value={id} />
          <button className="rounded-lg px-2.5 py-1.5 text-xs font-semibold text-red-500 hover:bg-red-50"><Tt>Delete</Tt></button>
        </form>
      </div>
    </li>
  );
}
