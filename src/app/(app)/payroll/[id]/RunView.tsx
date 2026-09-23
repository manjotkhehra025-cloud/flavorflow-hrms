import { Pa } from "@/components/Pa";

import Link from "next/link";
import { PayslipShareButtons } from "@/components/PayslipShareButtons";
import { Card, btnGhost } from "@/components/ui";
import { fmtINR } from "@/lib/utils";
import { Icon } from "@/components/icons";
import type { EditRow } from "./RunEditor";

export function RunView({ runId, rows }: { runId: string; month: string; rows: EditRow[] }) {
  return (
    <div className="space-y-4">
      <Card className="flex flex-wrap items-center gap-2 px-4 sm:px-6 py-4">
        <span className="mr-1 text-xs font-bold text-slate-700"><Pa>Excel downloads</Pa></span>
        {([["sheet", "Salary sheet"], ["register", "Salary register"], ["deductions", "Deductions & OT"]] as const).map(([kind, label]) => (
          <a key={kind} href={`/api/payroll/${runId}/excel?kind=${kind}`} className={btnGhost} download>
            <Icon name="download" className="h-3.5 w-3.5" /> <Pa>{label}</Pa>
          </a>
        ))}
      </Card>

      <Card className="p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[860px] text-xs">
            <thead>
              <tr className="bg-slate-50 text-left text-[10px] font-bold uppercase tracking-wider text-slate-500">
                <th className="px-3 py-2.5"><Pa>Employee</Pa></th>
                <th className="px-2 py-2.5 text-center"><Pa>Payable days</Pa></th>
                <th className="px-2 py-2.5 text-right"><Pa>Base ₹</Pa></th>
                <th className="px-2 py-2.5 text-right"><Pa>OT ₹</Pa></th>
                <th className="px-2 py-2.5 text-right"><Pa>Reward +</Pa></th>
                <th className="px-2 py-2.5 text-right"><Pa>Deductions −</Pa></th>
                <th className="px-2 py-2.5 text-right"><Pa>Adv. recover −</Pa></th>
                <th className="px-2 py-2.5 text-right"><Pa>Net ₹</Pa></th>
                <th className="px-2 py-2.5 text-center"><Pa>Payslip</Pa></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-t border-slate-100">
                  <td className="px-3 py-2.5">
                    <div className="font-bold text-slate-800">{r.code} · {r.name}</div>
                    <div className="text-[10px] text-slate-400">{r.dept}{r.bank ? " · " + r.bank : ""} · {r.paymentMode}</div>
                  </td>
                  <td className="px-2 py-2.5 text-center font-bold text-slate-700">
                    {r.payableDays}
                    <div className="text-[10px] font-normal text-slate-400">P{r.presentDays} L{r.leaveDays} O{r.offDays}{r.lopDays > 0 ? ` LOP${r.lopDays}` : ""}</div>
                  </td>
                  <td className="px-2 py-2.5 text-right font-semibold text-slate-700">{fmtINR(r.baseAmount)}</td>
                  <td className="px-2 py-2.5 text-right text-slate-600">{r.otAmount > 0 ? fmtINR(r.otAmount) : "—"}
                    {r.otHours > 0 && <div className="text-[10px] text-slate-400">{r.otHours}h × ₹{r.otRate}</div>}</td>
                  <td className="px-2 py-2.5 text-right text-emerald-600">
                    {[r.offWorkPay > 0 ? "+" + fmtINR(r.offWorkPay) : "", r.otherEarning > 0 ? "+" + fmtINR(r.otherEarning) : ""].filter(Boolean).join(" + ") || "—"}
                    {r.offWorkDays > 0 && <div className="text-[9.5px] text-slate-400">{r.offWorkDays} <Pa>off-duty day(s)</Pa></div>}
                  </td>
                  <td className="px-2 py-2.5 text-right text-rose-600">{(r.deductions + r.otherDeduction + r.pfEmployee + r.esiEmployee) > 0 ? "−" + fmtINR(r.deductions + r.otherDeduction + r.pfEmployee + r.esiEmployee) : "—"}
                    {(r.pfEmployee > 0 || r.esiEmployee > 0) && <div className="text-[9.5px] text-rose-400">{[r.pfEmployee > 0 ? `PF ${fmtINR(r.pfEmployee)}` : "", r.esiEmployee > 0 ? `ESI ${fmtINR(r.esiEmployee)}` : ""].filter(Boolean).join(" ")}</div>}</td>
                  <td className="px-2 py-2.5 text-right text-rose-600">{r.advanceRecover > 0 ? "−" + fmtINR(r.advanceRecover) : "—"}</td>
                  <td className="px-2 py-2.5 text-right font-black text-emerald-700">{fmtINR(r.netPay)}</td>
                  <td className="px-2 py-2.5 text-center whitespace-nowrap">
                    <div className="flex flex-col items-center gap-1">
                      <Link href={`/payroll/${runId}/payslip/${r.id}`} className={btnGhost} title="Payslip">
                        <Icon name="printer" className="h-3.5 w-3.5" />
                      </Link>
                      <PayslipShareButtons rowId={r.id} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
