import { Pa } from "@/components/Pa";
import QRCode from "qrcode";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { fmtDate, initials } from "@/lib/utils";
import { Card, PageHeader, Badge, inputCls } from "@/components/ui";
import { Icon } from "@/components/icons";

import { PrintButton } from "./PrintButton";
import { GatePassForm } from "./GatePassForm";
import { KycLocker } from "@/components/KycLocker";

export const dynamic = "force-dynamic";

const BASE_URL = process.env.NEXT_PUBLIC_BASE_URL ?? "https://hr.flavorflow.co.in";
const FACTORY_ADDR = "V.P.O. Khadur Sahib, Tarn Taran, Punjab, 143117, India";

export default async function IdCardPage({
  searchParams,
}: {
  searchParams: Promise<{ emp?: string }>;
}) {
  const me = await requireUser();
  const { emp: empParam } = await searchParams;
  const staff = me.role !== "EMPLOYEE";

  const allEmployees = staff
    ? await db.employee.findMany({
        where: { companyId: me.companyId, status: "ACTIVE" },
        include: { department: true },
        orderBy: { firstName: "asc" },
      })
    : [];

  const targetId = staff && empParam ? empParam : me.employeeId;
  const employee = targetId
    ? await db.employee.findFirst({
        where: { id: targetId, companyId: me.companyId },
        include: { department: true, designation: true, shift: true, users: { select: { role: true } } },
      })
    : null;

  const gatePasses = employee
    ? await db.gatePass.findMany({
        where: { employeeId: employee.id },
        orderBy: { createdAt: "desc" },
        take: 4,
      })
    : [];

  const name = employee ? `${employee.firstName} ${employee.lastName}` : "";
  const myDocs = employee && employee.id === me.employeeId ? await db.kycDoc.findMany({ where: { employeeId: employee.id }, orderBy: { createdAt: "desc" } }) : [];
  const roleChip = employee?.users[0]?.role === "ADMIN" ? "Super Admin" : employee?.users[0]?.role === "HR" ? "HR Manager" : null;
  const qr = employee
    ? await QRCode.toDataURL(`${BASE_URL}/verify/${employee.code}`, { margin: 1, width: 140, color: { dark: "#0a1628" } })
    : null;
  const isYellow = employee?.category === "YELLOW_CARD";

  return (
    <div>
      <PageHeader title={<Pa>ID Card & Gate Pass</Pa>} subtitle={<Pa>Official digital badge — scannable QR, flip details & gate passes.</Pa>} />

      {/* Staff: employee selector */}
      {staff && (
        <Card className="mb-5 p-4">
          <form className="flex flex-wrap items-center gap-3">
            <span className="text-xs font-semibold text-slate-500">{<Pa>Select Employee:</Pa>}</span>
            <select name="emp" defaultValue={employee?.id ?? ""} className={inputCls + " !w-auto min-w-64"}>
              {!me.employeeId && <option value="">—</option>}
              {allEmployees.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.firstName} {e.lastName} ({e.code}) — {e.department?.name ?? "—"} · {e.category === "YELLOW_CARD" ? "Yellow Card" : "Official"}
                </option>
              ))}
            </select>
            <button className="btn-ghost !py-2">{<Pa>Show</Pa>}</button>
          </form>
        </Card>
      )}

      {!employee ? (
        <Card className="p-6 text-sm text-slate-500">
          {me.employeeId ? "Employee not found." : "Your login isn't linked to an employee profile — ask HR to link it."}
        </Card>
      ) : (
        <div className="print-area mx-auto max-w-md space-y-4">
          <div className="flex justify-end print:hidden">
            <PrintButton />
          </div>

          {/* ===== FRONT ===== */}
          <div className="relative overflow-hidden rounded-3xl bg-[#0a1628] p-6 text-white shadow-pop">
            <div className="pointer-events-none absolute -right-14 -top-14 h-44 w-44 rounded-full bg-emerald-500/20 blur-3xl" />
            <div className="relative">
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-2.5">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-500/15 text-sm font-black text-emerald-400 ring-1 ring-emerald-400/30">{<Pa>GD</Pa>}</div>
                  <div className="leading-tight">
                    <div className="text-[13px] font-black tracking-tight">{me.companyName.toUpperCase()}</div>
                  </div>
                </div>
                {qr && (
                  <div className="text-center">
                    <div className="rounded-lg bg-white p-1"><img src={qr} alt="Verify QR" className="h-14 w-14" /></div>
                    <div className="mt-1 text-[8px] font-bold tracking-wider text-slate-400">{<Pa>SCAN FOR DETAILS</Pa>}</div>
                  </div>
                )}
              </div>

              <div className="mt-4 flex justify-center">
                <span className="rounded-full border border-amber-400/60 bg-amber-400/10 px-4 py-1 text-[11px] font-black tracking-wider text-amber-300">
                  {isYellow ? <Pa>YELLOW CARD STAFF</Pa> : <Pa>OFFICIAL STAFF</Pa>}
                </span>
              </div>

              <div className="mt-4 flex justify-center">
                {employee.photoUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={employee.photoUrl} alt={name} className="h-28 w-28 rounded-2xl object-cover ring-2 ring-emerald-400/40" />
                ) : (
                  <div className="flex h-28 w-28 items-center justify-center rounded-2xl bg-gradient-to-br from-slate-700 to-slate-800 text-3xl font-black text-emerald-300 ring-2 ring-emerald-400/40">
                    {initials(name)}
                  </div>
                )}
              </div>

              <h2 className="mt-4 text-center text-2xl font-black tracking-tight">{name}</h2>
              <p className="text-center text-sm font-bold text-emerald-400">{employee.department?.name ?? "—"}</p>
              {roleChip && (
                <div className="mt-1.5 flex justify-center">
                  <span className="rounded-full bg-slate-700/80 px-3 py-0.5 text-[11px] font-semibold text-slate-300">{roleChip}</span>
                </div>
              )}

              <div className="mt-5 flex items-center justify-between border-t border-white/10 pt-3 text-[11px]">
                <span className="font-semibold tracking-wider text-slate-400">ID: {employee.code}</span>
                <span className="flex items-center gap-1.5 font-bold text-emerald-400">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" /> {employee.status === "ACTIVE" ? <Pa>VERIFIED</Pa> : <Pa>INACTIVE</Pa>}
                </span>
              </div>
            </div>
          </div>

          {/* ===== BACK ===== */}
          <div className="rounded-3xl bg-[#0a1628] p-6 text-white shadow-pop">
            <h3 className="text-center text-sm font-black tracking-wider text-amber-400">
              {isYellow ? <Pa>YELLOW CARD BADGE</Pa> : <Pa>OFFICIAL STAFF BADGE</Pa>}
            </h3>
            <p className="mt-0.5 text-center text-[11px] text-slate-400">{me.companyName}</p>

            <div className="mt-4 space-y-0 border-t border-white/10">
              <InfoRow k={<Pa>Employee ID</Pa>} v={employee.code} />
              <InfoRow k={<Pa>DOJ</Pa>} v={fmtDate(employee.joinDate)} />
              <InfoRow k={<Pa>DOB</Pa>} v={employee.dateOfBirth ? fmtDate(employee.dateOfBirth) : "—"} />
              <InfoRow k={<Pa>Blood Group</Pa>} v={employee.bloodGroup ?? "—"} highlight />
              <InfoRow k={<Pa>Emergency Contact</Pa>} v={employee.emergencyPhone ? `${employee.emergencyName ? employee.emergencyName + " · " : ""}${employee.emergencyPhone}` : "—"} />
              <InfoRow k="Shift" v={employee.shift ? `${employee.shift.name} (${employee.shift.startTime})` : "General Day (08:00)"} />
            </div>

            <div className="mt-4 rounded-xl bg-white/[0.05] p-3.5">
              <div className="mb-1.5 text-[10px] font-black tracking-wider text-amber-400">{<Pa>INSTRUCTIONS:</Pa>}</div>
              <ol className="list-decimal space-y-1 pl-4 text-[11px] leading-relaxed text-slate-300">
                <li><Pa>This badge is property of</Pa> {me.companyName}.</li>
                <li>{<Pa>Must be displayed on duty. Weekly off applies per roster.</Pa>}</li>
                <li>{<Pa>Loss must be reported immediately to Security Gate / HR.</Pa>}</li>
              </ol>
            </div>

            <div className="mt-3 rounded-xl bg-white/[0.05] p-3.5 text-[11px]">
              <div className="font-bold text-slate-300">{<Pa>Factory Location:</Pa>}</div>
              <div className="mt-1 font-semibold text-emerald-400">{me.companyName}</div>
              <div className="text-slate-400">{FACTORY_ADDR}</div>
            </div>

            <div className="mt-4 flex items-center justify-between border-t border-white/10 pt-3 text-[10px] font-bold tracking-wider">
              <span className="text-slate-500">{me.companyName.toUpperCase()}</span>
              <span className="text-emerald-400">{<Pa>SECURITY VERIFIED</Pa>}</span>
            </div>
          </div>
        </div>
      )}

      {employee && employee.id === me.employeeId && (
        <div className="mx-auto mt-5 max-w-md">
          <KycLocker docs={myDocs.map((d) => ({ id: d.id, docType: d.docType, refNumber: d.refNumber }))} />
        </div>
      )}

      {/* ===== Gate Pass ===== */}
      {employee && (employee.id === me.employeeId || staff) && (
        <div className="mt-6">
          <GatePassForm isOwner={employee.id === me.employeeId} targetEmployeeId={employee.id} passes={gatePasses.map((g) => ({
            id: g.id, date: fmtDate(g.date), exitAt: g.exitAt, returnAt: g.returnAt,
            reason: g.reason, status: g.status, verified: !!g.entryVerifiedAt,
          }))} />
        </div>
      )}
    </div>
  );
}

function InfoRow({ k, v, highlight }: { k: React.ReactNode; v: string; highlight?: boolean }) {
  return (
    <div className="flex items-center justify-between border-b border-white/[0.07] py-2 text-[13px]">
      <span className="text-slate-400">{k}</span>
      <span className={highlight ? "font-black text-amber-400" : "font-semibold text-white"}>{v}</span>
    </div>
  );
}
