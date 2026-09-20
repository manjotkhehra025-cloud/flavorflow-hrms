import { cx } from "@/lib/utils";
import { Icon, type IconName } from "./icons";

export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return <div className={cx("card", className)}>{children}</div>;
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: React.ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 className="text-xl font-bold tracking-tight text-slate-900 md:text-2xl">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-slate-500">{subtitle}</p>}
      </div>
      {actions}
    </div>
  );
}

const TONES = {
  green: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
  red: "bg-red-50 text-red-700 ring-red-600/20",
  amber: "bg-amber-50 text-amber-700 ring-amber-600/25",
  slate: "bg-slate-100 text-slate-600 ring-slate-500/20",
  blue: "bg-sky-50 text-sky-700 ring-sky-600/20",
} as const;

const DOTS = {
  green: "bg-emerald-500",
  red: "bg-red-500",
  amber: "bg-amber-500",
  slate: "bg-slate-400",
  blue: "bg-sky-500",
} as const;

export function Badge({ tone, children }: { tone: keyof typeof TONES; children: React.ReactNode }) {
  return (
    <span className={cx("badge", TONES[tone])}>
      <span className={cx("h-1.5 w-1.5 rounded-full", DOTS[tone])} />
      {children}
    </span>
  );
}

export function StatCard({
  label,
  value,
  icon,
  tone,
  href,
}: {
  label: string;
  value: number | string;
  icon: IconName;
  tone: "amber" | "emerald" | "rose" | "sky";
  href?: string;
}) {
  const tones = {
    amber: "bg-amber-500/15 text-amber-600",
    emerald: "bg-emerald-500/15 text-emerald-600",
    rose: "bg-rose-500/15 text-rose-600",
    sky: "bg-sky-500/15 text-sky-600",
  };
  const inner = (
    <Card className="group p-5 transition-all hover:-translate-y-0.5 hover:shadow-[var(--shadow-pop)]">
      <div className="flex items-start justify-between">
        <div>
          <div className="text-3xl font-extrabold tracking-tight text-slate-900">{value}</div>
          <div className="mt-1 text-sm font-medium text-slate-500">{label}</div>
        </div>
        <div className={cx("flex h-11 w-11 items-center justify-center rounded-xl transition-transform group-hover:scale-110", tones[tone])}>
          <Icon name={icon} className="h-5.5 w-5.5" />
        </div>
      </div>
    </Card>
  );
  return href ? <a href={href}>{inner}</a> : inner;
}

export function EmptyState({ icon, title, hint }: { icon: IconName; title: string; hint?: string }) {
  return (
    <div className="flex flex-col items-center justify-center px-4 py-12 text-center">
      <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-slate-100 text-slate-400">
        <Icon name={icon} className="h-6 w-6" />
      </div>
      <p className="text-sm font-semibold text-slate-600">{title}</p>
      {hint && <p className="mt-1 text-xs text-slate-400">{hint}</p>}
    </div>
  );
}

export const inputCls = "input";
export const btnPrimary = "btn-dark";
export const btnBrand = "btn-brand";
export const btnGhost = "btn-ghost";
