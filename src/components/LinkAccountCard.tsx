"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "@/components/icons";
import { linkSelfToEmployeeAction } from "@/actions/account";

type Option = { id: string; label: string };

export function LinkAccountCard({ employees }: { employees: Option[] }) {
  const router = useRouter();
  const [selected, setSelected] = useState(employees[0]?.id ?? "");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (employees.length === 0) {
    return (
      <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-6 text-white shadow-[var(--shadow-pop)]">
        <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-amber-500/20 blur-3xl" />
        <div className="relative flex items-start gap-4">
          <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-amber-400/15 ring-1 ring-amber-300/25">
            <Icon name="users" className="h-5 w-5 text-amber-300" />
          </span>
          <div>
            <p className="text-sm font-extrabold tracking-tight">Punch button missing?</p>
            <p className="mt-1 text-xs leading-relaxed text-slate-400">
              Your login isn&apos;t linked to any employee profile, and every existing profile already has a login.
              <br />
              <b className="text-slate-200">Karne layi:</b> Employees → Add New → bas apni details bharo
              (<b className="text-amber-200">&quot;Has login account&quot; tick NAHI karna</b> — tuhada login pehlaan hi hai) →
              save. Fer es thaan card ch tuhadi profile dikhegi, &quot;Link &amp; Continue&quot; dabao — punch turant chal pauga.
            </p>
          </div>
        </div>
      </div>
    );
  }

  function link() {
    if (!selected) return;
    setError(null);
    startTransition(async () => {
      const res = await linkSelfToEmployeeAction(selected);
      if (res?.ok) router.refresh();
      else setError(res?.error ?? "Could not link. Try again.");
    });
  }

  return (
    <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-6 text-white shadow-[var(--shadow-pop)]">
      <div className="pointer-events-none absolute -right-16 -top-16 h-52 w-52 rounded-full bg-emerald-500/20 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-20 -left-12 h-40 w-40 rounded-full bg-teal-500/10 blur-3xl" />
      <div className="relative">
        <div className="flex items-start gap-4">
          <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-emerald-400/15 ring-1 ring-emerald-300/25">
            <Icon name="link" className="h-5 w-5 text-emerald-300" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-emerald-400/90">One-time setup</p>
            <p className="mt-0.5 text-sm font-extrabold tracking-tight">Link your login to your employee profile</p>
            <p className="mt-1 text-xs leading-relaxed text-slate-400">
              Punch, attendance, leave balance &amp; TOPS sab es link ton bina nahi chalda. Pick your own profile below —
              sirf ek wari karna hai.
            </p>
          </div>
        </div>

        <div className="mt-5 flex flex-col gap-2.5 sm:flex-row">
          <div className="relative flex-1">
            <select
              value={selected}
              onChange={(e) => setSelected(e.target.value)}
              className="w-full appearance-none rounded-xl border border-white/10 bg-white/[0.06] px-4 py-3 text-sm font-semibold text-white outline-none ring-emerald-400/40 transition focus:ring-2 [&>option]:bg-[#0a1628]"
            >
              {employees.map((e) => (
                <option key={e.id} value={e.id}>{e.label}</option>
              ))}
            </select>
            <Icon name="chevron-down" className="pointer-events-none absolute right-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
          </div>
          <button
            onClick={link}
            disabled={pending || !selected}
            className="flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-emerald-500 to-emerald-600 px-6 py-3 text-sm font-bold text-white shadow-[0_10px_30px_-6px_rgb(16_185_129_/_60%)] transition hover:from-emerald-400 hover:to-emerald-500 active:scale-[0.98] disabled:opacity-50"
          >
            <Icon name="fingerprint" className="h-4.5 w-4.5" />
            {pending ? "Linking…" : "Link & Continue"}
          </button>
        </div>
        {error && <p className="mt-3 text-xs font-semibold text-rose-300">{error}</p>}
      </div>
    </div>
  );
}
