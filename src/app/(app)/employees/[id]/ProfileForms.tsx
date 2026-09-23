"use client";
import { Tt, useT } from "@/components/LangCtx";

import { useActionState, useState } from "react";
import { updateEmployeeDetailsAction } from "@/actions/employees";
import { adjustLeaveBalanceAction } from "@/actions/requests";
import type { ActionState } from "@/actions/auth";
import { inputCls, btnBrand, btnGhost } from "@/components/ui";
import { Icon } from "@/components/icons";

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"];

type DeptOpt = { id: string; name: string; parentId?: string | null; hasSubs?: boolean };
type Emp = {
  id: string;
  category: string;
  departmentId?: string | null;
  designationId?: string | null;
  weeklyOff: number;
  shiftId: string | null;
  bloodGroup: string | null;
  emergencyPhone: string | null;
  phone: string | null;
  dateOfBirth: string | null;
  contractor: string | null;
};

export function ProfileForms({
  employee,
  shifts,
  leaveTypes,
  isYellow,
  departments = [],
  designations = [],
}: {
  employee: Emp;
  shifts: { id: string; name: string }[];
  leaveTypes: { id: string; name: string; quota: number }[];
  isYellow: boolean;
  departments?: DeptOpt[];
  designations?: { id: string; title: string; category?: string }[];
}) {
  const ph = useT();
  const [editState, editAction, editPending] = useActionState<ActionState, FormData>(updateEmployeeDetailsAction, {});
  const [adjState, adjAction, adjPending] = useActionState<ActionState, FormData>(adjustLeaveBalanceAction, {});
  const [openEdit, setOpenEdit] = useState(false);
  const [openAdj, setOpenAdj] = useState(false);
  const [draftCat, setDraftCat] = useState<string>(employee.category);
  const desigOptions = draftCat === "YELLOW_CARD"
    ? designations.filter((d) => d.category === "YELLOW_CARD")
    : designations.filter((d) => !d.category || d.category === "BOTH" || d.category === "OFFICIAL");
  const deptOptions = draftCat === "YELLOW_CARD"
    ? departments.filter((d) => d.parentId || !d.hasSubs)
    : departments;

  const balanceTypes = isYellow ? leaveTypes.filter((t) => /earned/i.test(t.name)) : leaveTypes.filter((t) => t.quota > 0);

  return (
    <div className="mt-6 space-y-3">
      {/* Edit HR details */}
      <button onClick={() => setOpenEdit(!openEdit)} className={btnGhost + " w-full justify-center"}>
        <Icon name="sliders" className="h-4 w-4" /> {openEdit ? "Hide editor" : "Edit HR details"}
      </button>
      {openEdit && (
        <form action={editAction} className="space-y-3 rounded-2xl border border-emerald-200 bg-emerald-50/40 p-4">
          {editState.error && <p className="mb-1 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{editState.error}</p>}
          {editState.success && <p className="mb-1 rounded-lg bg-emerald-100 px-3 py-2 text-sm text-emerald-800">{editState.success}</p>}
          <input type="hidden" name="employeeId" value={employee.id} />
          <div className="grid grid-cols-2 gap-3">
            <label className="col-span-2 block text-xs font-semibold text-slate-600">
              Staff category
              <select name="category" value={draftCat} onChange={(e) => setDraftCat(e.target.value)} className={inputCls + " mt-1"}>
                <option value="OFFICIAL">{<Tt>Official Staff</Tt>}</option>
                <option value="YELLOW_CARD">{<Tt>Yellow Card</Tt>}</option>
              </select>
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              <Tt>Department</Tt>
              <select name="departmentId" defaultValue={employee.departmentId ?? ""} className={inputCls + " mt-1"}>
                <option value="">—</option>
                {deptOptions.map((d) => (
                  <option key={d.id} value={d.id}>{d.name}</option>
                ))}
              </select>
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              <Tt>Designation</Tt>
              <select name="designationId" defaultValue={employee.designationId ?? ""} className={inputCls + " mt-1"}>
                <option value="">—</option>
                {desigOptions.map((d) => (
                  <option key={d.id} value={d.id}>{d.title}</option>
                ))}
              </select>
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              Weekly off
              <select name="weeklyOff" defaultValue={String(employee.weeklyOff)} className={inputCls + " mt-1"}>
                {WEEKDAYS.map((d, i) => (
                  <option key={d} value={i}>{d}</option>
                ))}
              </select>
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              Shift
              <select name="shiftId" defaultValue={employee.shiftId ?? ""} className={inputCls + " mt-1"}>
                <option value="">{<Tt>General (default)</Tt>}</option>
                {shifts.map((s) => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </select>
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              <Tt>Blood group</Tt>
              <select name="bloodGroup" defaultValue={employee.bloodGroup ?? ""} className={inputCls + " mt-1"}>
                <option value="">—</option>
                {BLOOD_GROUPS.map((g) => <option key={g} value={g}>{g}</option>)}
              </select>
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              Emergency contact
              <input name="emergencyPhone" defaultValue={employee.emergencyPhone ?? ""} placeholder="+91…" className={inputCls + " mt-1"} />
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              Phone
              <input name="phone" defaultValue={employee.phone ?? ""} className={inputCls + " mt-1"} />
            </label>
            <label className="block text-xs font-semibold text-slate-600">
              Date of birth
              <input type="date" name="dateOfBirth" defaultValue={employee.dateOfBirth ?? ""} className={inputCls + " mt-1"} />
            </label>
            <label className="col-span-2">
              <span className="text-xs font-semibold text-slate-600"><Tt>Contractor / thekedari (optional, paid-via-labour staff)</Tt></span>
              <input name="contractor" defaultValue={employee.contractor ?? ""} placeholder={ph("e.g. Verma Labour Contractor")} className={inputCls + " mt-1"} />
            </label>
          </div>
          <button disabled={editPending} className={btnBrand + " w-full justify-center"}>{editPending ? "Saving…" : "Save details"}</button>
        </form>
      )}

      {/* Adjust leave balance */}
      <span id="adjust" />
      <button onClick={() => setOpenAdj(!openAdj)} className={btnGhost + " w-full justify-center"}>
        <Icon name="sliders" className="h-4 w-4" /> {openAdj ? "Hide adjust" : "Adjust leave balance"}
      </button>
      {openAdj && (
        <form action={adjAction} className="space-y-3 rounded-2xl border border-amber-200 bg-amber-50/40 p-4">
          {adjState.error && <p className="mb-1 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{adjState.error}</p>}
          {adjState.success && <p className="mb-1 rounded-lg bg-emerald-100 px-3 py-2 text-sm text-emerald-800">{adjState.success}</p>}
          <input type="hidden" name="employeeId" value={employee.id} />
          <label className="block text-xs font-semibold text-slate-600">
            Leave type
            <select name="leaveTypeId" className={inputCls + " mt-1"} required>
              {balanceTypes.map((t) => (
                <option key={t.id} value={t.id}>{t.name}</option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-slate-600">
            Days (+ adds balance, − deducts, e.g. 2 or -1)
            <input type="number" name="days" step="0.5" placeholder={ph("e.g. 2 or -1")} className={inputCls + " mt-1"} required />
          </label>
          <label className="block text-xs font-semibold text-slate-600">
            Note (optional)
            <input name="note" placeholder={ph("Correction for August gate pass…")} className={inputCls + " mt-1"} />
          </label>
          <button disabled={adjPending} className={btnBrand + " w-full justify-center"}>{adjPending ? "Saving…" : "Apply adjustment"}</button>
        </form>
      )}
    </div>
  );
}
