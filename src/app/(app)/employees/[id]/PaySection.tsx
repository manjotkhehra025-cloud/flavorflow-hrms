"use client";
import { Tt, useT } from "@/components/LangCtx";

import { useActionState, useState } from "react";
import { updateSalaryAction, addAdvanceAction, deleteAdvanceAction } from "@/actions/pay";
import type { ActionState } from "@/actions/auth";
import { Card, inputCls, btnBrand } from "@/components/ui";
import { Icon } from "@/components/icons";

type Props = {
  employee: {
    id: string;
    salaryType: string;
    baseSalary: number | null;
    dailyRate: number | null;
    otRate: number | null;
    bankAccount: string | null;
    ifsc: string | null;
    pfEnabled: boolean;
    pfNumber: string | null;
    esiEnabled: boolean;
    esiNumber: string | null;
  };
  advances: {
    id: string;
    amount: number;
    repaid: number;
    emi: number | null;
    givenDate: string; // dd MMM yyyy
    reason: string | null;
  }[];
};

function fmt(n: number): string {
  return "₹ " + n.toLocaleString("en-IN");
}

/** Suggested OT/hr: base/26/9 monthly · rate/9 daily */
function autoOt(e: Props["employee"], type: string, base: number | null, daily: number | null): number | null {
  if (type === "DAILY") return daily ? Math.round(daily / 9) : null;
  return base ? Math.round(base / 26 / 9) : null;
}

export function PaySection({ employee, advances }: Props) {
  const ph = useT();
  const [state, action, pending] = useActionState<ActionState, FormData>(updateSalaryAction, {});
  const [advState, advAction, advPending] = useActionState<ActionState, FormData>(addAdvanceAction, {});
  const [type, setType] = useState(employee.salaryType === "DAILY" ? "DAILY" : "MONTHLY");
  const [base, setBase] = useState(employee.baseSalary);
  const [daily, setDaily] = useState(employee.dailyRate);
  const [pfOn, setPfOn] = useState(employee.pfEnabled);
  const [esiOn, setEsiOn] = useState(employee.esiEnabled);

  const suggestion = autoOt(employee, type, base, daily);
  const totalBalance = advances.reduce((s, a) => s + (a.amount - a.repaid), 0);

  return (
    <Card className="mt-6 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-slate-900"><Tt>Pay & advances 💵</Tt></h3>
        {totalBalance > 0 && (
          <span className="rounded-full bg-rose-50 px-2.5 py-1 text-[10px] font-bold text-rose-600">
            <Tt>Advance balance</Tt>: {fmt(totalBalance)}
          </span>
        )}
      </div>

      <form action={action} className="space-y-4">
        <input type="hidden" name="employeeId" value={employee.id} />
        <input type="hidden" name="salaryType" value={type} />

        {/* model toggle */}
        <div className="flex gap-2">
          {(["MONTHLY", "DAILY"] as const).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setType(t)}
              className={`flex-1 rounded-xl border-2 px-3 py-2 text-xs font-bold transition ${
                type === t ? "border-emerald-500 bg-emerald-50 text-emerald-700" : "border-slate-200 text-slate-500 hover:border-slate-300"
              }`}
              disabled={pending}
            >
              {t === "MONTHLY" ? <Tt>Monthly salary</Tt> : <Tt>Daily-rate</Tt>}
            </button>
          ))}
        </div>

        {/* statutory */}
        <div className="rounded-xl border border-slate-100 bg-slate-50/60 p-3">
          <div className="mb-2 text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Statutory (India)</Tt></div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <label className={"flex items-start gap-2 rounded-lg border-2 px-3 py-2 cursor-pointer " + (pfOn ? "border-emerald-500 bg-emerald-50" : "border-slate-200 bg-white")}>
              <input type="checkbox" name="pfEnabled" className="mt-1" checked={pfOn} onChange={(e) => setPfOn(e.target.checked)} />
              <span className="text-xs">
                <b><Tt>PF / EPF</Tt></b> — <Tt>12% employee + 12% employer</Tt>
                {pfOn && <input name="pfNumber" className="mt-1.5 w-full rounded-md border border-slate-200 px-2 py-1" placeholder={ph("UAN number")} defaultValue={employee.pfNumber ?? ""} />}
              </span>
            </label>
            <label className={"flex items-start gap-2 rounded-lg border-2 px-3 py-2 cursor-pointer " + (esiOn ? "border-emerald-500 bg-emerald-50" : "border-slate-200 bg-white")}>
              <input type="checkbox" name="esiEnabled" className="mt-1" checked={esiOn} onChange={(e) => setEsiOn(e.target.checked)} />
              <span className="text-xs">
                <b><Tt>ESI</Tt></b> — <Tt>0.75% employee + 3.25% employer</Tt>
                {esiOn && <input name="esiNumber" className="mt-1.5 w-full rounded-md border border-slate-200 px-2 py-1" placeholder={ph("IP / insurance no.")} defaultValue={employee.esiNumber ?? ""} />}
              </span>
            </label>
          </div>
          <p className="mt-1.5 text-[10.5px] text-slate-400">
            <Tt>Suggested for salary ≤ ₹15,000 (PF) and ≤ ₹21,000 (ESI). PF cap ₹1,800 above ₹15,000.</Tt>
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3">
          {type === "MONTHLY" ? (
            <label className="col-span-2 sm:col-span-1">
              <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Base salary / month ₹</Tt></span>
              <input
                name="baseSalary" type="number" min={1} inputMode="numeric" className={inputCls}
                defaultValue={employee.baseSalary ?? ""} onChange={(e) => setBase(parseInt(e.target.value) || null)}
                placeholder="11000" required
              />
            </label>
          ) : (
            <label className="col-span-2 sm:col-span-1">
              <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Daily rate ₹</Tt></span>
              <input
                name="dailyRate" type="number" min={1} inputMode="numeric" className={inputCls}
                defaultValue={employee.dailyRate ?? ""} onChange={(e) => setDaily(parseInt(e.target.value) || null)}
                placeholder="450" required
              />
            </label>
          )}
          <label className="col-span-2 sm:col-span-1">
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500">
              <Tt>OT rate / hour ₹</Tt>{" "}
              <span className="text-slate-400">{suggestion ? ph("(auto ₹") + suggestion + ")" : ph("(auto)")}</span>
            </span>
            <input
              name="otRate" type="number" min={1} inputMode="numeric" className={inputCls}
              defaultValue={employee.otRate ?? ""} placeholder={suggestion ? String(suggestion) : ph("e.g. 58")}
            />
          </label>
          <label className="col-span-2 sm:col-span-1">
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Bank account no.</Tt></span>
            <input name="bankAccount" className={inputCls} defaultValue={employee.bankAccount ?? ""} placeholder={ph("12-digit account number")} />
          </label>
          <label className="col-span-2 sm:col-span-1">
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>IFSC</Tt></span>
            <input name="ifsc" className={inputCls} defaultValue={employee.ifsc ?? ""} placeholder="SBIN0123456" style={{ textTransform: "uppercase" }} />
          </label>
        </div>

        {type === "MONTHLY" && base && !employee.otRate && suggestion && (
          <p className="rounded-lg bg-sky-50 px-3 py-2 text-[11px] text-sky-700">
            <Tt>OT auto-filled from base</Tt>: ₹{base} ÷ 26 <Tt>days</Tt> ÷ 9h ≈ <b>₹{suggestion}/hr</b>
          </p>
        )}
        {state?.error && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{state.error}</p>}
        {state?.success && <p className="rounded-lg bg-emerald-100 px-3 py-2 text-sm text-emerald-800">{state.success}</p>}
        <button type="submit" className={btnBrand} disabled={pending}>
          {pending ? <Tt>Saving…</Tt> : <Tt>Save salary setup</Tt>}
        </button>
      </form>

      {/* advance ledger */}
      <div className="mt-6 border-t border-slate-100 pt-4">
        <h4 className="mb-2 text-xs font-bold uppercase tracking-wide text-slate-500"><Tt>Advance ledger 🪙</Tt></h4>
        {advances.length === 0 ? (
          <p className="text-xs text-slate-400"><Tt>No advances given yet</Tt></p>
        ) : (
          <ul className="space-y-2">
            {advances.map((a) => {
              const balance = a.amount - a.repaid;
              return (
                <li key={a.id} className="flex items-center gap-3 rounded-xl border border-slate-100 px-3.5 py-2.5">
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-bold text-slate-800">{fmt(a.amount)}</div>
                    <div className="truncate text-[11px] text-slate-500">
                      <Tt>given</Tt> {a.givenDate}{a.reason ? ` · ${a.reason}` : ""}{a.emi ? ` · ` : ""}{a.emi && <span className="font-bold text-indigo-600"><Tt>EMI</Tt> ₹{a.emi}/mo</span>} ·{" "}
                      {balance === 0 ? (
                        <span className="font-semibold text-emerald-600"><Tt>fully recovered</Tt> ✓</span>
                      ) : (
                        <span className="font-semibold text-rose-600"><Tt>balance</Tt> {fmt(balance)}</span>
                      )}
                    </div>
                  </div>
                  {a.repaid === 0 && (
                    <form action={async (fd: FormData) => {
                      await deleteAdvanceAction({} as ActionState, fd);
                      window.location.reload();
                    }}>
                      <input type="hidden" name="advanceId" value={a.id} />
                      <button type="submit" className="btn-ghost !px-2.5 !py-1.5 text-[10px]" title="Delete">
                        <Icon name="x" className="h-3.5 w-3.5" />
                      </button>
                    </form>
                  )}
                </li>
              );
            })}
          </ul>
        )}

        <form action={advAction} className="mt-3 flex flex-wrap items-end gap-2">
          <input type="hidden" name="employeeId" value={employee.id} />
          <label className="flex-1 min-w-[110px]">
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Amount ₹</Tt></span>
            <input name="amount" type="number" min={1} inputMode="numeric" className={inputCls} placeholder="2000" required />
          </label>
          <label className="flex-1 min-w-[120px]">
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Given date</Tt></span>
            <input name="givenDate" type="date" className={inputCls} />
          </label>
          <label className="flex-[2] min-w-[140px]">
            <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.1em] text-slate-500"><Tt>Reason (optional)</Tt></span>
            <input name="reason" className={inputCls} placeholder={ph("e.g. family need")} />
            <input name="emi" type="number" min={0} inputMode="numeric" className={inputCls} placeholder={ph("EMI ₹/month (optional)")} title="Fixed monthly recovery; empty = auto 25% rule" />
          </label>
          <button type="submit" className={`${btnBrand} !px-3.5`} disabled={advPending}>
            {advPending ? "…" : <Tt>+ Add advance</Tt>}
          </button>
          {advState?.error && <p className="w-full rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{advState.error}</p>}
          {advState?.success && <p className="w-full rounded-lg bg-emerald-100 px-3 py-2 text-sm text-emerald-800">{advState.success}</p>}
        </form>
        <p className="mt-2 text-[10.5px] text-slate-400">
          <Tt>Advances auto-deduct in payroll — recovery cap promotes the rest to next month.</Tt>
        </p>
      </div>
    </Card>
  );
}
