"use client";
import { Tt, useT } from "@/components/LangCtx";

import { useActionState, useState } from "react";
import { createEmployeeAction } from "@/actions/employees";
import type { ActionState } from "@/actions/auth";
import { inputCls, btnBrand } from "@/components/ui";

type Opt = { id: string; name?: string; title?: string; category?: string };
const BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"];
type ShiftOpt = { id: string; name: string; startTime: string };

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

export function NewEmployeeForm({ departments, designations, shifts }: { departments: Opt[]; designations: Opt[]; shifts: ShiftOpt[] }) {
  const ph = useT();
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createEmployeeAction, {});
  const [category, setCategory] = useState<"OFFICIAL" | "YELLOW_CARD">("OFFICIAL");
  // Staff-type-aware designation list (BOTH visible to everyone)
  const desigOptions = designations.filter((d) => !d.category || d.category === "BOTH" || d.category === category);

  return (
    <form action={formAction} className="space-y-5">
      {state.error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="First name *"><input name="firstName" required className={inputCls} /></Field>
        <Field label="Last name *"><input name="lastName" required className={inputCls} /></Field>
        <Field label="Email"><input name="email" type="email" className={inputCls} placeholder={ph("name@gdfoods.co.in")} /></Field>
        <Field label="Phone"><input name="phone" className={inputCls} placeholder="+91…" /></Field>
        <Field label="Staff category">
          <select name="category" value={category} onChange={(e) => setCategory(e.target.value as "OFFICIAL" | "YELLOW_CARD")} className={inputCls}>
            <option value="OFFICIAL">{<Tt>Official Staff</Tt>}</option>
            <option value="YELLOW_CARD">{<Tt>Yellow Card (15 EL / yr)</Tt>}</option>
          </select>
        </Field>
        <Field label="Weekly off">
          <select name="weeklyOff" className={inputCls}>
            {WEEKDAYS.map((d, i) => (
              <option key={d} value={i}>{d}</option>
            ))}
          </select>
        </Field>
        <Field label="Shift">
          <select name="shiftId" className={inputCls}>
            <option value="">{<Tt>General Day (default)</Tt>}</option>
            {shifts.map((s) => (
              <option key={s.id} value={s.id}>{s.name} ({s.startTime})</option>
            ))}
          </select>
        </Field>
        <Field label="Blood group">
          <select name="bloodGroup" className={inputCls}>
            <option value="">—</option>
            {BLOOD_GROUPS.map((g) => <option key={g} value={g}>{g}</option>)}
          </select>
        </Field>
        <Field label="Emergency contact"><input name="emergencyPhone" className={inputCls} placeholder="+91…" /></Field>
        <Field label="Gender">
          <select name="gender" className={inputCls}>
            <option value="">—</option>
            <option>{<Tt>Male</Tt>}</option>
            <option>{<Tt>Female</Tt>}</option>
            <option>{<Tt>Other</Tt>}</option>
          </select>
        </Field>
        <Field label="Joining date *"><input name="joinDate" type="date" required className={inputCls} /></Field>
        <Field label="Department">
          <select name="departmentId" className={inputCls}>
            <option value="">—</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>{d.name}</option>
            ))}
          </select>
        </Field>
        <Field label="Designation">
          <select name="designationId" className={inputCls}>
            <option value="">—</option>
            {desigOptions.map((d) => (
              <option key={d.id} value={d.id}>
                {d.title}{d.category === "YELLOW_CARD" ? " (Yellow Card)" : d.category === "OFFICIAL" ? " (Official)" : ""}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Date of birth"><input name="dateOfBirth" type="date" className={inputCls} /></Field>
      </div>

      <Field label="Address">
        <textarea name="address" rows={2} className={inputCls} />
      </Field>

      <div className="group/login space-y-0 rounded-2xl border border-slate-200 p-4 transition has-[:checked]:border-emerald-300 has-[:checked]:bg-emerald-50/40">
        <div className="flex items-center gap-3">
          <input
            id="hs-login"
            type="checkbox"
            name="createAccount"
            className="h-4.5 w-4.5 shrink-0 accent-emerald-500"
          />
          <label htmlFor="hs-login" className="cursor-pointer select-none">
            <span className="text-sm font-bold text-slate-800">{<Tt>Has login account</Tt>}</span>
            <span className="block text-xs text-slate-500">{<Tt>Needed for self punch-in, leave requests &amp; gate pass</Tt>}</span>
          </label>
        </div>

        {/* CSS-only reveal — phone te JS slow/fail howe taan vi 100% visible */}
        <div className="hidden pt-4 group-has-[:checked]/login:grid">
          <div className="grid gap-4 rounded-xl bg-white p-4 ring-1 ring-emerald-200/60 sm:grid-cols-2">
            <Field label="Role">
              <select name="accountRole" className={inputCls}>
                <option value="EMPLOYEE">{<Tt>Employee</Tt>}</option>
                <option value="HR">{<Tt>HR (can manage people & leaves)</Tt>}</option>
              </select>
            </Field>
            <Field label="Temporary password (min 8 chars)">
              <input name="tempPassword" type="text" minLength={8} className={inputCls} placeholder={ph("Share with the employee")} />
            </Field>
            <p className="text-xs text-slate-500 sm:col-span-2">
              Login email = <b>{<Tt>the Email field above</Tt>}</b>{<Tt>(required when creating a login). After saving, the employees list shows a</Tt>}<b className="text-emerald-600">{<Tt>✓ Login</Tt>}</b> chip.
            </p>
          </div>
        </div>
      </div>

      <div className="flex justify-end gap-2">
        <button type="submit" disabled={pending} className={btnBrand}>
          {pending ? "Saving…" : "Save employee"}
        </button>
      </div>
    </form>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="mb-1 block text-sm font-medium text-slate-700">{label}</label>
      {children}
    </div>
  );
}
