import type { RegisterGrid as Grid } from "@/lib/reports2";

const CELL_TONE: Record<string, string> = {
  P: "bg-emerald-100 text-emerald-700",
  A: "bg-red-100 text-red-600",
  L: "bg-amber-100 text-amber-700",
  W: "bg-blue-100 text-blue-700",
  H: "bg-violet-100 text-violet-700",
};

/** Days × employees attendance register — horizontally scrollable, sticky name column. */
export function RegisterGrid({ grid }: { grid: Grid }) {
  const days = Array.from({ length: grid.daysInMonth }, (_, i) => i + 1);
  const totals = grid.rows.reduce(
    (t, r) => ({ P: t.P + r.present, A: t.A + r.absent, L: t.L + r.leave, W: t.W + r.weeklyOff }),
    { P: 0, A: 0, L: 0, W: 0 }
  );

  return (
    <div className="overflow-x-auto rounded-xl border border-slate-100">
      <table className="w-full border-collapse text-[11px]">
        <thead>
          <tr>
            <th className="sticky left-0 z-10 min-w-[130px] bg-slate-50 px-2.5 py-2 text-left text-[10px] font-bold uppercase tracking-wide text-slate-500">
              Employee
            </th>
            {days.map((d) => (
              <th
                key={d}
                className={`min-w-[30px] px-0 py-2 text-center text-[9.5px] font-bold ${
                  grid.sundays[d - 1] ? "bg-slate-200 text-slate-600" : "bg-slate-50 text-slate-500"
                }`}
              >
                {d}
              </th>
            ))}
            {["P", "A", "L", "W"].map((h) => (
              <th key={h} className="min-w-[30px] bg-emerald-600 px-0 py-2 text-center text-[10px] font-extrabold text-white">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {grid.rows.map((r) => (
            <tr key={r.employeeId} className="border-t border-slate-50 hover:bg-slate-50/60">
              <td className="sticky left-0 z-10 bg-white px-2.5 py-1.5">
                <div className="truncate text-[11px] font-semibold text-slate-800">{r.name}</div>
                <div className="text-[8.5px] text-slate-400">{r.code}</div>
              </td>
              {r.cells.map((c, i) => (
                <td key={i} className="py-1.5 text-center">
                  {c.code ? (
                    <span
                      title={c.inAt ? `Checked in at ${c.inAt}` : c.note ?? undefined}
                      className={`mx-auto flex h-[19px] w-[19px] items-center justify-center rounded-md text-[9px] font-extrabold ${CELL_TONE[c.code]}`}
                    >
                      {c.code}
                    </span>
                  ) : (
                    <span className="text-slate-200">·</span>
                  )}
                </td>
              ))}
              <td className="px-0 py-1.5 text-center font-extrabold text-emerald-700">{r.present}</td>
              <td className={`px-0 py-1.5 text-center font-extrabold ${r.absent ? "text-red-600" : "text-slate-300"}`}>{r.absent}</td>
              <td className="px-0 py-1.5 text-center font-bold text-amber-600">{r.leave}</td>
              <td className="px-0 py-1.5 text-center font-bold text-blue-600">{r.weeklyOff}</td>
            </tr>
          ))}
          {grid.rows.length > 0 && (
            <tr className="border-t-2 border-slate-200 bg-slate-50/70">
              <td className="sticky left-0 z-10 bg-slate-50 px-2.5 py-1.5 text-[10px] font-extrabold text-slate-700">
                All ({grid.rows.length})
              </td>
              {days.map((d) => (
                <td key={d}></td>
              ))}
              <td className="py-1.5 text-center text-[11px] font-extrabold text-emerald-700">{totals.P}</td>
              <td className="py-1.5 text-center text-[11px] font-extrabold text-red-600">{totals.A}</td>
              <td className="py-1.5 text-center text-[11px] font-extrabold text-amber-600">{totals.L}</td>
              <td className="py-1.5 text-center text-[11px] font-extrabold text-blue-600">{totals.W}</td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
