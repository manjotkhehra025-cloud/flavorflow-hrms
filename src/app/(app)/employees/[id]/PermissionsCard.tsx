"use client";

import { useState, useTransition } from "react";
import { Card } from "@/components/ui";
import { useLang } from "@/components/LangCtx";
import { setEmployeePermissionAction } from "@/actions/permissions";

type PermKey =
  | "canPunch"
  | "canApplyLeave"
  | "canGatePass"
  | "canSwapShift"
  | "canSocialPost"
  | "canViewPayslip";

const ROWS: { key: PermKey; labelEn: string; labelPa: string; hintEn: string; hintPa: string; icon: string }[] = [
  { key: "canPunch", labelEn: "Self punch (check-in/out)", labelPa: "ਖ਼ੁਦ ਪੰਚ (ਅੰਦਰ/ਬਾਹਰ)", hintEn: "GPS punch + manual punch requests", hintPa: "GPS ਪੰਚ + ਮੈਨੁਅਲ ਪੰਚ ਬੇਨਤੀਆਂ", icon: "⏱" },
  { key: "canApplyLeave", labelEn: "Leave requests", labelPa: "ਛੁੱਟੀ ਦੀਆਂ ਬੇਨਤੀਆਂ", hintEn: "Apply for leaves from the app", hintPa: "ਐਪ ਤੋਂ ਛੁੱਟੀ ਲਈ ਅਰਜ਼ੀ", icon: "🌿" },
  { key: "canGatePass", labelEn: "Gate pass requests", labelPa: "ਗੇਟ ਪਾਸ ਬੇਨਤੀਆਂ", hintEn: "QR gate passes for exit/entry", hintPa: "ਬਾਹਰ ਜਾਣ ਲਈ QR ਗੇਟ ਪਾਸ", icon: "🎫" },
  { key: "canSwapShift", labelEn: "Shift swaps", labelPa: "ਸ਼ਿਫਟ ਅਦਲਾ-ਬਦਲੀ", hintEn: "Swap a shift day with a teammate", hintPa: "ਸਾਥੀ ਨਾਲ ਛੁੱਟੀ/ਸ਼ਿਫਟ ਬਦਲਣੀਆਂ", icon: "⇄" },
  { key: "canSocialPost", labelEn: "Social Wall posting", labelPa: "ਸੋਸ਼ਲ ਵਾਲ ਤੇ ਪੋਸਟ", hintEn: "Post & comment on the company wall", hintPa: "ਕੰਪਨੀ ਵਾਲ ਤੇ ਪੋਸਟ/ਟਿੱਪਣੀ", icon: "💬" },
  { key: "canViewPayslip", labelEn: "Payslip viewing", labelPa: "ਪੇ-ਸਲਿੱਪ ਵੇਖਣਾ", hintEn: "See own salary slips in the app", hintPa: "ਆਪਣੀਆਂ ਤਨਖ਼ਾਹ ਸਲਿੱਪਾਂ ਵੇਖਣੀਆਂ", icon: "💰" },
];

export function PermissionsCard({ employeeId, initial }: { employeeId: string; initial: Record<PermKey, boolean> }) {
  const lang = useLang();
  const [state, setState] = useState(initial);
  const [pending, start] = useTransition();
  return (
    <Card className="p-5">
      <h3 className="mb-1 flex items-center gap-2 font-display text-sm font-semibold text-slate-800">
        <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-violet-100 text-sm">🔐</span>
        {lang === "pa" ? "ਫੀਚਰ ਇਜਾਜ਼ਤਾਂ" : "Feature permissions"}
        <span className="ml-1 rounded-full bg-violet-50 px-2 py-0.5 text-[9px] font-bold uppercase tracking-wide text-violet-600">
          {lang === "pa" ? "ਸਿਰਫ਼ ਸੁਪਰ ਐਡਮਿਨ" : "Super admin"}
        </span>
      </h3>
      <p className="mb-3 text-[11px] text-slate-400">
        {lang === "pa" ? "ਹਰ employee ਲਈ ਹਰ feature ਤੁਸੀਂ on/off ਕਰ ਸਕਦੇ ਹੋ — band feature ਤੇ employee nu note ਦਿਖੇਗਾ." : "Turn each feature on/off for this employee. Locked features show a note instead."}
      </p>
      <ul className="divide-y divide-slate-100">
        {ROWS.map((r) => {
          const on = state[r.key];
          return (
            <li key={r.key} className="flex items-center gap-3 py-2.5">
              <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-sm ${on ? "bg-emerald-50" : "bg-rose-50"}`}>{r.icon}</span>
              <div className="min-w-0 flex-1">
                <p className="text-[13px] font-semibold text-slate-700">{lang === "pa" ? r.labelPa : r.labelEn}</p>
                <p className="text-[11px] text-slate-400">{lang === "pa" ? r.hintPa : r.hintEn}</p>
              </div>
              <button
                type="button"
                disabled={pending}
                onClick={() => {
                  const next = { ...state, [r.key]: !on };
                  setState(next); // optimistic
                  start(async () => {
                    try {
                      await setEmployeePermissionAction(employeeId, r.key, !on);
                    } catch {
                      setState(state); // rollback
                      alert(lang === "pa" ? "Update ਅਸਫਲ ਰਿਹਾ" : "Update failed");
                    }
                  });
                }}
                className={[
                  "relative h-6 w-11 shrink-0 rounded-full transition-colors duration-200",
                  on ? "bg-emerald-500" : "bg-slate-300",
                  pending ? "opacity-60" : "",
                ].join(" ")}
                aria-label={`Toggle ${r.labelEn}`}
              >
                <span
                  className="absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all duration-200"
                  style={{ left: on ? "22px" : "2px" }}
                />
              </button>
            </li>
          );
        })}
      </ul>
    </Card>
  );
}
