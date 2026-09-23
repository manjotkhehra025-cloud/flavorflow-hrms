import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { getRecentActivity } from "@/lib/activity";
import { timeAgo } from "@/lib/utils";
import { Tt } from "@/components/LangCtx";
import { Icon } from "@/components/icons";
import { PageHeader } from "@/components/ui";

export const dynamic = "force-dynamic";

export default async function ActivityPage() {
  const me = await requireUser();
  const items = await getRecentActivity(me, 60);
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <PageHeader title={<Tt>Recent activity</Tt>} subtitle={<Tt>Everything that's happened lately — punches, approvals, letters, wall posts.</Tt>} />
      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
        <ul className="divide-y divide-slate-100">
          {items.map((a, i) => (
            <li key={i}>
              <Link href={a.href} className="flex items-start gap-3 px-4 py-3 transition hover:bg-emerald-50/40">
                <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500">
                  <Icon name={a.icon} className="h-4 w-4" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-sm leading-snug text-slate-700"><b className="font-extrabold text-slate-800">{a.actor}</b> {a.text}</span>
                  <span className="mt-0.5 block text-[11px] font-semibold text-slate-400">{timeAgo(a.at)}</span>
                </span>
              </Link>
            </li>
          ))}
          {items.length === 0 && <li className="px-4 py-10 text-center text-sm text-slate-400"><Tt>All quiet for now.</Tt></li>}
        </ul>
      </div>
    </div>
  );
}
