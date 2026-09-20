"use client";

import { useActionState, useState } from "react";
import { createEmployeeAction } from "@/actions/employees";
import type { ActionState } from "@/actions/auth";
import { inputCls, btnBrand } from "@/components/ui";

type Opt = { id: string; name?: string; title?: string };

export function NewEmployeeForm({ departments, designations }: { departments: Opt[]; designations: Opt[] }) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(createEmployeeAction, {});
  const [createAccount, setCreateAccount] = useState(false);

  return (
    <form action={formAction} className="space-y-5">
      {state.error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="First name *"><input name="firstName" required className={inputCls} /></Field>
        <Field label="Last name *"><input name="lastName" required className={inputCls} /></Field>
        <Field label="Email"><input name="email" type="email" className={inputCls} placeholder="name@flavorflow.co.in" /></Field>
        <Field label="Phone"><input name="phone" className={inputCls} placeholder="+91…" /></Field>
        <Field label="Gender">
          <select name="gender" className={inputCls}>
            <option value="">—</option>
            <option>Male</option>
            <option>Female</option>
            <option>Other</option>
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
            {designations.map((d) => (
              <option key={d.id} value={d.id}>{d.title}</option>
            ))}
          </select>
        </Field>
      </div>

      <Field label="Address">
        <textarea name="address" rows={2} className={inputCls} />
      </Field>

      <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
        <input
          type="checkbox"
          name="createAccount"
          checked={createAccount}
          onChange={(e) => setCreateAccount(e.target.checked)}
          className="h-4 w-4 accent-amber-500"
        />
        Give this person a login (for self check-in & leave requests)
      </label>

      {createAccount && (
        <div className="grid gap-4 rounded-xl bg-slate-50 p-4 sm:grid-cols-2">
          <Field label="Role">
            <select name="accountRole" className={inputCls}>
              <option value="EMPLOYEE">Employee</option>
              <option value="HR">HR (can manage people & leaves)</option>
            </select>
          </Field>
          <Field label="Temporary password (min 8 chars)">
            <input name="tempPassword" type="text" minLength={8} className={inputCls} placeholder="Share with the employee" />
          </Field>
        </div>
      )}

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
