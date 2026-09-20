import { cx } from "@/lib/utils";

export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cx("rounded-2xl border border-slate-200 bg-white shadow-sm", className)}>
      {children}
    </div>
  );
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: React.ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-slate-500">{subtitle}</p>}
      </div>
      {actions}
    </div>
  );
}

export function Badge({ tone, children }: { tone: "green" | "red" | "amber" | "slate" | "blue"; children: React.ReactNode }) {
  const tones = {
    green: "bg-emerald-50 text-emerald-700 ring-emerald-200",
    red: "bg-red-50 text-red-700 ring-red-200",
    amber: "bg-amber-50 text-amber-700 ring-amber-200",
    slate: "bg-slate-100 text-slate-600 ring-slate-200",
    blue: "bg-sky-50 text-sky-700 ring-sky-200",
  };
  return (
    <span className={cx("inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset", tones[tone])}>
      {children}
    </span>
  );
}

export const inputCls =
  "w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-200 bg-white";

export const btnPrimary =
  "rounded-lg bg-slate-950 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800 disabled:opacity-50";

export const btnBrand =
  "rounded-lg bg-amber-500 px-4 py-2 text-sm font-semibold text-slate-950 hover:bg-amber-400 disabled:opacity-50";

export const btnGhost =
  "rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50";
