"use client";
import { Tt, useT } from "@/components/LangCtx";

import { Fragment, useActionState, useMemo, useState } from "react";
import Link from "next/link";
import { saveRosterAction } from "@/actions/roster";
import type { ActionState } from "@/actions/auth";
import { Card, btnBrand, btnGhost } from "@/components/ui";
import { Icon } from "@/components/icons";

type Emp = { id: string; code: string; name: string; dept: string; defShift: string | null };
type CellKey = string; // empId|yyyy-mm-dd

const DAY_TAG: Record<string, string> = { "0": "Sun", "1": "Mon", "2": "Tue", "3": "Wed", "4": "Thu", "5": "Fri", "6": "Sat" };

export function RosterGrid({
  employees, shifts, days, grid, prevW, nextW,
}: {
  employees: Emp[];
  shifts: { id: string; name: string; startTime: string }[];
  days: string[];
  grid: Record<CellKey, { shiftId: string; isOff: boolean }>;
  prevW: string; nextW: string;
}) {
  const ph = useT();
  const [state, action, pending] = useActionState<ActionState, FormData>(saveRosterAction, {});
  const [edits, setEdits] = useState<Record<CellKey, { shiftId: string; isOff: boolean }>>({});
  const dirty = Object.keys(edits).length > 0;

  const cell = (empId: string, day: string): { shiftId: string; isOff: boolean } =>
    edits[empId + "|" + day] ?? grid[empId + "|" + day] ?? { shiftId: "", isOff: false };

  const grouped = useMemo(() => {
    const m = new Map<string, Emp[]>();
    for (const e of employees) {
      if (!m.has(e.dept)) m.set(e.dept, []);
      m.get(e.dept)!.push(e);
    }
    return m;
  }, [employees]);

  function setCell(empId: string, day: string, value: string) {
    const next = value === "__OFF" ? { shiftId: "", isOff: true } : { shiftId: value, isOff: false };
    setEdits((e) => {
      const k = empId + "|" + day;
      const base = grid[k] ?? { shiftId: "", isOff: false };
      const eq = base.shiftId === next.shiftId && base.isOff === next.isOff;
      const cp = { ...e };
      if (eq) delete cp[k]; else cp[k] = next;
      return cp;
    });
  }

  function submit(fd: FormData) {
    const entries = Object.entries(edits).map(([k, v]) => {
      const [employeeId, date] = k.split("|");
      return { employeeId, date, shiftId: v.shiftId || null, isOff: v.isOff };
    });
    fd.set("entries", JSON.stringify(entries));
    return action(fd);
  }

  return (
    <Card className="p-0 overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-4 sm:px-6 py-3">
        <div className="flex items-center gap-2">
          <Link href={`/roster?w=${prevW}`} className={`${btnGhost} !px-2.5`}><Icon name="chevron-down" className="h-3.5 w-3.5 rotate-90" /></Link>
          <span className="text-sm font-bold text-slate-800">
            {days[0].slice(8, 10)}–{days[6].slice(8, 10)} {new Date(days[6] + "T00:00:00.000Z").toLocaleString("en-IN", { month: "long", timeZone: "UTC" })}
          </span>
          <Link href={`/roster?w=${nextW}`} className={`${btnGhost} !px-2.5`}><Icon name="chevron-down" className="h-3.5 w-3.5 -rotate-90" /></Link>
        </div>
        <form action={submit}>
          <button type="submit" className={btnBrand} disabled={!dirty || pending}>
            {pending ? <Tt>Saving…</Tt> : dirty ? <Tt>Save roster</Tt> : <Tt>Saved ✓</Tt>}
          </button>
        </form>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[820px] text-xs">
          <thead>
            <tr className="bg-slate-50 text-left text-[10px] font-bold uppercase tracking-wider text-slate-500">
              <th className="px-3 py-2.5 sticky left-0 bg-slate-50 min-w-[200px]"><Tt>Employee</Tt></th>
              {days.map((d) => {
                const dt = new Date(d + "T00:00:00.000Z");
                const isToday = d === new Date().toISOString().slice(0, 10);
                return (
                  <th key={d} className={"px-2 py-2.5 text-center min-w-[92px] " + (isToday ? "text-emerald-600" : "")}>
                    <div>{DAY_TAG[String(dt.getUTCDay())]}</div>
                    <div className={"text-sm " + (isToday ? "font-black" : "font-bold")}>{d.slice(8, 10)}</div>
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {[...grouped.entries()].map(([dept, emps]) => (
              <Fragment key={dept}>
                <tr className="bg-emerald-50/60">
                  <td colSpan={8} className="px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.12em] text-emerald-700">{dept}</td>
                </tr>
                {emps.map((e) => (
                  <tr key={e.id} className="border-t border-slate-100">
                    <td className="px-3 py-2 sticky left-0 bg-white">
                      <div className="font-bold text-slate-800">{e.code} · {e.name}</div>
                      <div className="text-[10px] text-slate-400"><Tt>default</Tt>: {e.defShift ?? "—"}</div>
                    </td>
                    {days.map((d) => {
                      const v = cell(e.id, d);
                      const value = v.isOff ? "__OFF" : v.shiftId;
                      const override = value !== "" || v.isOff;
                      return (
                        <td key={d} className="px-1.5 py-1.5">
                          <select
                            value={v.isOff ? "__OFF" : v.shiftId}
                            onChange={(ev) => setCell(e.id, d, ev.target.value)}
                            className={
                              "w-full rounded-lg border px-1.5 py-1.5 text-[11px] font-semibold " +
                              (v.isOff
                                ? "border-rose-300 bg-rose-50 text-rose-600"
                                : override
                                  ? "border-emerald-400 bg-emerald-50 text-emerald-700"
                                  : "border-slate-200 bg-white text-slate-500")
                            }
                          >
                            <option value=""><Tt>default</Tt></option>
                            {shifts.map((s) => (
                              <option key={s.id} value={s.id}>{s.name} · {s.startTime}</option>
                            ))}
                            <option value="__OFF"><Tt>OFF</Tt></option>
                          </select>
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>

      <div className="flex items-center gap-3 border-t border-slate-100 px-4 sm:px-6 py-3 text-[11px] text-slate-500">
        <span className="inline-block h-3 w-3 rounded border border-slate-200" /> {ph("uses default shift")}
        <span className="inline-block h-3 w-3 rounded border border-emerald-400 bg-emerald-50" /> {ph("shift override")}
        <span className="inline-block h-3 w-3 rounded border border-rose-300 bg-rose-50" /> {ph("day off")}
      </div>
      {state?.error && <p className="mx-4 mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>}
      {state?.success && <p className="mx-4 mb-3 rounded-lg bg-emerald-100 px-3 py-2 text-sm text-emerald-800">{state.success}</p>}
    </Card>
  );
}
