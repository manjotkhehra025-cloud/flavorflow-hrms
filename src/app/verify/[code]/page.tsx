import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { fmtDate, initials } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function VerifyPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const emp = await db.employee.findFirst({
    where: { code: decodeURIComponent(code) },
    include: { company: true, department: true, designation: true },
  });
  if (!emp) notFound();

  const name = `${emp.firstName} ${emp.lastName}`;
  const active = emp.status === "ACTIVE";

  return (
    <div className="flex min-h-screen items-center justify-center bg-[#0a1628] p-4">
      <div className="w-full max-w-sm overflow-hidden rounded-3xl bg-white shadow-2xl">
        <div className="bg-[#0a1628] p-6 text-center text-white">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-emerald-500/15 text-lg font-black text-emerald-400 ring-1 ring-emerald-400/30">
            {emp.company.name.slice(0, 2).toUpperCase()}
          </div>
          <div className="mt-2 text-xs font-black tracking-wide text-slate-300">{emp.company.name.toUpperCase()}</div>
          <div className="text-[10px] font-semibold tracking-[0.2em] text-emerald-400">HRMATE IDENTITY VERIFICATION</div>
        </div>
        <div className="p-6">
          <div className="flex items-center gap-4">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-slate-700 to-slate-800 text-xl font-black text-emerald-300">
              {initials(name)}
            </div>
            <div className="min-w-0">
              <h1 className="truncate text-lg font-black text-slate-900">{name}</h1>
              <p className="text-xs font-semibold text-slate-500">{emp.department?.name ?? "—"}{emp.designation ? ` · ${emp.designation.title}` : ""}</p>
              <span className={`mt-1 inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[10px] font-black tracking-wide ${
                active ? "bg-emerald-50 text-emerald-600" : "bg-red-50 text-red-600"
              }`}>
                <span className={`h-1.5 w-1.5 rounded-full ${active ? "bg-emerald-500" : "bg-red-500"}`} />
                {active ? "● ACTIVE EMPLOYEE" : "INACTIVE"}
              </span>
            </div>
          </div>
          <div className="mt-5 space-y-0 border-t border-slate-100">
            <Row k="Employee ID" v={emp.code} />
            <Row k="Staff Category" v={emp.category === "YELLOW_CARD" ? "🟡 Yellow Card" : "🔵 Official"} />
            <Row k="Date of Joining" v={fmtDate(emp.joinDate)} />
          </div>
          <p className="mt-5 rounded-xl bg-slate-50 p-3 text-center text-[11px] leading-relaxed text-slate-500">
            This document confirms the individual identified above is a registered member of our workforce.
          </p>
        </div>
      </div>
    </div>
  );
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex items-center justify-between border-b border-slate-50 py-2.5 text-sm">
      <span className="text-slate-500">{k}</span>
      <span className="font-semibold text-slate-800">{v}</span>
    </div>
  );
}
