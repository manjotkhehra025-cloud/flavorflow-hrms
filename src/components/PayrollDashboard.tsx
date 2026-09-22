import { Pa } from "@/components/Pa";
import { Card } from "@/components/ui";
import { fmtINR, monthName } from "@/lib/utils";

type RunLite = {
  month: string;
  status: string;
  net: number;
  employer: number; // PF+ESI employer cost
  staff: number;
};
type DeptRow = { label: string; net: number; staff: number; isContractor?: boolean };

/** Pure-CSS bars — no chart library, reads at a glance on a phone. */
export function PayrollDashboard({
  runs, deptSplit, contractorSplit, latestMonth,
}: {
  runs: RunLite[];
  deptSplit: DeptRow[];
  contractorSplit: DeptRow[];
  latestMonth: string | null;
}) {
  const maxNet = Math.max(1, ...runs.map((r) => r.net));
  const maxDept = Math.max(1, ...deptSplit.map((d) => d.net));

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {/* monthly cost trend */}
      <Card className="p-5">
        <div className="mb-3 flex items-baseline justify-between">
          <h3 className="text-sm font-bold text-slate-900"><Pa>Salary cost trend</Pa></h3>
          <span className="text-[10px] text-slate-400"><Pa>last runs</Pa></span>
        </div>
        {runs.length === 0 ? (
          <p className="text-xs text-slate-400"><Pa>Trend appears after your first payroll.</Pa></p>
        ) : (
          <div className="space-y-2.5">
            {runs.map((r) => (
              <div key={r.month}>
                <div className="flex justify-between text-[11px]">
                  <span className="font-semibold text-slate-700">{monthName(r.month)}</span>
                  <span className="font-black text-slate-900">{fmtINR(r.net)}{r.employer > 0 && <span className="ml-1 font-semibold text-slate-400">+{fmtINR(r.employer)}</span>}</span>
                </div>
                <div className="mt-1 h-2.5 overflow-hidden rounded-full bg-slate-100">
                  <div className="flex h-full">
                    <div className="rounded-l-full bg-gradient-to-r from-emerald-500 to-emerald-600" style={{ width: `${(r.net / maxNet) * 100}%` }} />
                    {r.employer > 0 && <div className="bg-amber-400/80" style={{ width: `${(r.employer / maxNet) * 100}%` }} />}
                  </div>
                </div>
              </div>
            ))}
            <p className="pt-1 text-[10px] text-slate-400"><Pa>Green = net payout · amber = employer PF+ESI (company's own cost)</Pa></p>
          </div>
        )}
      </Card>

      {/* dept + contractor split */}
      <Card className="p-5">
        <div className="mb-3 flex items-baseline justify-between">
          <h3 className="text-sm font-bold text-slate-900"><Pa>Where the money goes</Pa></h3>
          {latestMonth && <span className="text-[10px] font-semibold text-slate-400">{monthName(latestMonth)}</span>}
        </div>
        {deptSplit.length === 0 ? (
          <p className="text-xs text-slate-400"><Pa>Lock a run to see the split.</Pa></p>
        ) : (
          <div className="space-y-2">
            {deptSplit.map((d) => (
              <div key={d.label} className="flex items-center gap-2 text-[11px]">
                <span className="w-24 truncate font-semibold text-slate-600">{d.label}</span>
                <div className="relative h-4 flex-1 overflow-hidden rounded-md bg-slate-100">
                  <div className="h-full rounded-md bg-emerald-500/85" style={{ width: `${Math.max(2, (d.net / maxDept) * 100)}%` }} />
                </div>
                <span className="w-20 text-right font-bold text-slate-800">{fmtINR(d.net)}</span>
                <span className="w-10 text-right text-[10px] text-slate-400">{d.staff}👤</span>
              </div>
            ))}
            {contractorSplit.length > 0 && (
              <>
                <div className="pt-2 text-[9.5px] font-bold uppercase tracking-[0.12em] text-slate-400"><Pa>Contractor / thekedari</Pa></div>
                {contractorSplit.map((d) => (
                  <div key={d.label} className="flex items-center gap-2 text-[11px]">
                    <span className="w-24 truncate font-semibold text-amber-700">{d.label}</span>
                    <div className="relative h-4 flex-1 overflow-hidden rounded-md bg-slate-100">
                      <div className="h-full rounded-md bg-amber-400/80" style={{ width: `${Math.max(2, (d.net / maxDept) * 100)}%` }} />
                    </div>
                    <span className="w-20 text-right font-bold text-slate-800">{fmtINR(d.net)}</span>
                    <span className="w-10 text-right text-[10px] text-slate-400">{d.staff}👤</span>
                  </div>
                ))}
              </>
            )}
          </div>
        )}
      </Card>
    </div>
  );
}
