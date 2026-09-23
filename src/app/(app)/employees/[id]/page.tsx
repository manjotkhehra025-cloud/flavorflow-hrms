import { Pa } from "@/components/Pa";
import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { fmtDate, initials, fmtTime, todayDate } from "@/lib/utils";
import { Card, PageHeader, Badge, btnGhost } from "@/components/ui";
import { updateEmployeeStatusAction, deleteEmployeeAction } from "@/actions/employees";
import { getLeaveBalances, balanceRemaining } from "@/lib/balances";
import { ProfileForms } from "./ProfileForms";
import { PaySection } from "./PaySection";
import { LetterSection } from "./LetterSection";
import { AdminResetButton } from "@/components/PasswordCards";
import { PhotoUpload } from "@/components/PhotoUpload";
import { AvatarImg } from "@/components/AvatarImg";

export const dynamic = "force-dynamic";

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function SalaryHistory({ revisions }: { revisions: { id: string; effectiveDate: string; changeType: string; oldType: string | null; newType: string | null; oldAmt: number | null; newAmt: number | null }[] }) {
  if (revisions.length === 0) return <Card className="mt-6 p-6 text-xs text-slate-400"><Pa>No salary revisions yet.</Pa></Card>;
  const chip: Record<string, string> = { RAISE: "bg-emerald-100 text-emerald-700", DEMOTE: "bg-rose-100 text-rose-700", CREATE: "bg-sky-100 text-sky-700", MODEL_SWITCH: "bg-violet-100 text-violet-700", REVISION: "bg-slate-100 text-slate-600" };
  const label: Record<string, string> = { RAISE: "Raise ↑", DEMOTE: "Demote ↓", CREATE: "Created", MODEL_SWITCH: "Model switch", REVISION: "Edit" };
  return (
    <Card className="mt-6 p-6">
      <h3 className="mb-3 text-sm font-semibold text-slate-900"><Pa>Pay history 📈</Pa></h3>
      <ul className="space-y-2 text-xs">
        {revisions.map((r) => (
          <li key={r.id} className="flex items-center gap-2 rounded-lg border border-slate-100 px-3 py-2">
            <span className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${chip[r.changeType] ?? chip.REVISION}`}>{label[r.changeType] ?? r.changeType}</span>
            <span className="font-semibold text-slate-800">
              {r.oldAmt != null ? `₹${r.oldAmt.toLocaleString("en-IN")}` : "—"} → <b>₹{(r.newAmt ?? 0).toLocaleString("en-IN")}</b>
              {r.oldType !== r.newType && <span className="ml-1 text-slate-400">({r.oldType}→{r.newType})</span>}
            </span>
            <span className="ml-auto text-[10px] text-slate-400">{r.effectiveDate}</span>
          </li>
        ))}
      </ul>
    </Card>
  );
}

export default async function EmployeeDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireStaff();
  const { id } = await params;

  const employee = await db.employee.findFirst({
    where: { id, companyId: me.companyId },
    include: {
      department: true,
      designation: true,
      shift: true,
      users: { select: { id: true, email: true, role: true, isActive: true } },
      advances: { orderBy: { givenDate: "desc" } },
      salaryRevisions: { orderBy: { createdAt: "desc" }, take: 12 },
    },
  });
  if (!employee) notFound();

  const monthStart = new Date(Date.UTC(todayDate().getUTCFullYear(), todayDate().getUTCMonth(), 1));
  const [attendance, leaves, balances, shifts, leaveTypes, letters, kycDocs] = await Promise.all([
    db.attendance.findMany({
      where: { employeeId: employee.id, date: { gte: monthStart } },
      orderBy: { date: "desc" },
      take: 31,
    }),
    db.leaveRequest.findMany({
      where: { employeeId: employee.id },
      include: { leaveType: true },
      orderBy: { createdAt: "desc" },
      take: 10,
    }),
    getLeaveBalances(employee, me.companyId),
    db.shift.findMany({ where: { companyId: me.companyId }, orderBy: { startTime: "asc" } }),
    db.leaveType.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" } }),
    db.letter.findMany({ where: { employeeId: employee.id }, orderBy: { createdAt: "desc" } }),
    db.kycDoc.findMany({ where: { employeeId: employee.id }, orderBy: { createdAt: "desc" } }),
  ]);

  const bindToggle = updateEmployeeStatusAction.bind(
    null,
    employee.id,
    employee.status === "ACTIVE" ? "INACTIVE" : "ACTIVE"
  );
  const isYellow = employee.category === "YELLOW_CARD";

  return (
    <div>
      <PageHeader
        title={`${employee.firstName} ${employee.lastName}`}
        subtitle={`${employee.code} · ${employee.designation?.title ?? "No designation"}`}
        actions={
          <div className="flex flex-wrap gap-2">
            <Link href={`/idcard?emp=${employee.id}`} className={btnGhost}>{<Pa>ID Card</Pa>}</Link>
            <form action={bindToggle}>
              <button className={btnGhost}>
                {employee.status === "ACTIVE" ? "Deactivate" : "Reactivate"}
              </button>
            </form>
            {me.role === "ADMIN" && (
              <form action={deleteEmployeeAction.bind(null, employee.id)}>
                <button className="rounded-lg border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50">
                  Delete
                </button>
              </form>
            )}
          </div>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="p-6">
          <div className="flex flex-col items-center text-center">
            <AvatarImg
              name={`${employee.firstName} ${employee.lastName}`}
              photoUrl={employee.photoUrl}
              size="h-20 w-20"
              textSize="text-2xl"
            />
            <h2 className="mt-3 text-lg font-bold text-slate-900">
              {employee.firstName} {employee.lastName}
            </h2>
            <div className="mt-1.5 flex flex-wrap justify-center gap-1.5">
              <Badge tone={employee.status === "ACTIVE" ? "green" : "slate"}>{employee.status}</Badge>
              <Badge tone={isYellow ? "amber" : "blue"}>{isYellow ? "🟡 Yellow Card" : "🔵 Official"}</Badge>
            </div>
            <PhotoUpload employeeId={employee.id} hasPhoto={!!employee.photoUrl} />
          </div>
          <dl className="mt-6 space-y-3 text-sm">
            <Row k="Email" v={employee.email ?? "—"} />
            <Row k="Phone" v={employee.phone ?? "—"} />
            <Row k="Blood Group" v={employee.bloodGroup ?? "—"} />
            <Row k="Emergency Contact" v={employee.emergencyPhone ?? "—"} />
            <Row k="DOB" v={employee.dateOfBirth ? fmtDate(employee.dateOfBirth) : "—"} />
            <Row k="Department" v={employee.department?.name ?? "—"} />
            <Row k="Designation" v={employee.designation?.title ?? "—"} />
            <Row k="Shift" v={employee.shift ? `${employee.shift.name} (${employee.shift.startTime}, ${employee.shift.durationH}h)` : "General (default)"} />
            <Row k="Weekly Off" v={WEEKDAYS[employee.weeklyOff]} />
            <Row k="Joined" v={fmtDate(employee.joinDate)} />
            <Row k="Gender" v={employee.gender ?? "—"} />
            <Row k="Address" v={employee.address ?? "—"} />
            <Row
              k="Login"
              v={employee.users[0] ? `${employee.users[0].email} (${employee.users[0].role})` : "No account"}
            />
          </dl>
          {employee.users[0] && me.role !== "EMPLOYEE" && (
            <AdminResetButton userId={employee.users[0].id} name={employee.firstName} />
          )}

          <ProfileForms
            employee={{
              id: employee.id,
              category: employee.category,
              weeklyOff: employee.weeklyOff,
              shiftId: employee.shiftId,
              bloodGroup: employee.bloodGroup,
              emergencyPhone: employee.emergencyPhone,
              phone: employee.phone,
              dateOfBirth: employee.dateOfBirth?.toISOString().slice(0, 10) ?? null,
              contractor: employee.contractor,
            }}
            shifts={shifts.map((s) => ({ id: s.id, name: s.name }))}
            leaveTypes={leaveTypes.map((t) => ({ id: t.id, name: t.name, quota: t.daysPerYear }))}
            isYellow={isYellow}
          />

          <PaySection
            employee={{
              id: employee.id,
              salaryType: employee.salaryType,
              baseSalary: employee.baseSalary,
              dailyRate: employee.dailyRate,
              otRate: employee.otRate,
              bankAccount: employee.bankAccount,
              ifsc: employee.ifsc,
              pfEnabled: employee.pfEnabled,
              pfNumber: employee.pfNumber,
              esiEnabled: employee.esiEnabled,
              esiNumber: employee.esiNumber,
            }}
            advances={employee.advances.map((a) => ({
              id: a.id,
              amount: a.amount,
              repaid: a.repaid,
              emi: a.emi,
              givenDate: fmtDate(a.givenDate),
              reason: a.reason,
            }))}
          />

          <SalaryHistory revisions={employee.salaryRevisions.map((r) => ({
            id: r.id, effectiveDate: fmtDate(r.effectiveDate), changeType: r.changeType,
            oldType: r.oldSalaryType, newType: r.newSalaryType,
            oldAmt: r.oldSalary, newAmt: r.newSalary,
          }))} />

          <LetterSection
            employeeId={employee.id}
            canEdit={me.role !== "EMPLOYEE"}
            kycDocs={kycDocs.map((d) => ({ id: d.id, docType: d.docType, refNumber: d.refNumber, createdAt: d.createdAt.toISOString() }))}
            letters={letters.map((l) => ({ id: l.id, serial: l.serial, type: l.type, issuedTo: l.issuedTo, createdAt: l.createdAt.toISOString() }))}
          />
        </Card>

        <Card className="p-6 lg:col-span-2">
          <h3 className="mb-4 text-sm font-semibold text-slate-900">{<Pa>This month's attendance</Pa>}</h3>
          {attendance.length === 0 ? (
            <p className="text-sm text-slate-500">{<Pa>No attendance records yet this month.</Pa>}</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                    <th className="py-2 pr-4">{<Pa>Date</Pa>}</th>
                    <th className="py-2 pr-4">{<Pa>In</Pa>}</th>
                    <th className="py-2 pr-4">{<Pa>Out</Pa>}</th>
                    <th className="py-2">{<Pa>Status</Pa>}</th>
                  </tr>
                </thead>
                <tbody>
                  {attendance.map((a) => (
                    <tr key={a.id} className="border-b border-slate-100 last:border-0">
                      <td className="py-2 pr-4 font-medium text-slate-700">{fmtDate(a.date)}</td>
                      <td className="py-2 pr-4 text-slate-600">{fmtTime(a.checkIn)}</td>
                      <td className="py-2 pr-4 text-slate-600">{fmtTime(a.checkOut)}</td>
                      <td className="py-2">
                        <Badge tone={a.status === "PRESENT" ? "green" : "amber"}>{a.status}</Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <h3 className="mb-3 mt-8 text-sm font-semibold text-slate-900">
            Leave balance ({new Date().getFullYear()}){isYellow ? " — EL 15·auto" : ""}
          </h3>
          <div className="mb-6 grid grid-cols-2 gap-2">
            {balances.map((b) => {
              const left = balanceRemaining(b);
              const consumed = Math.max(b.used + b.adjusted, 0);
              return (
                <div key={b.leaveTypeId} className="rounded-xl bg-slate-50 px-3.5 py-2.5 text-sm">
                  <div className="text-xs text-slate-500">{b.name}</div>
                  <div className="font-bold text-slate-800">
                    {b.quota === 0
                      ? `${consumed} taken`
                      : left !== null
                        ? `${left} left ${isYellow ? `(accrued ${b.accrued})` : `of ${b.quota}`}`
                        : `${consumed} taken`}
                    {b.pending > 0 && <span className="ml-1.5 text-xs font-medium text-amber-600">+{b.pending} pending</span>}
                  </div>
                </div>
              );
            })}
          </div>

          <h3 className="mb-4 text-sm font-semibold text-slate-900">{<Pa>Recent leave requests</Pa>}</h3>
          {leaves.length === 0 ? (
            <p className="text-sm text-slate-500">{<Pa>No leave requests yet.</Pa>}</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {leaves.map((l) => (
                <li key={l.id} className="flex items-center justify-between">
                  <span className="text-slate-700">
                    {l.leaveType.name} · {fmtDate(l.fromDate)} – {fmtDate(l.toDate)}
                  </span>
                  <Badge tone={l.status === "APPROVED" ? "green" : l.status === "REJECTED" ? "red" : l.status === "CANCELLED" ? "slate" : "amber"}>
                    {l.status}
                  </Badge>
                </li>
              ))}
            </ul>
          )}
          <div className="mt-6">
            <Link href="/employees" className="text-sm text-slate-500 hover:underline">{<Pa>← Back to employees</Pa>}</Link>
          </div>
        </Card>
      </div>
    </div>
  );
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-slate-500">{k}</dt>
      <dd className="text-right font-medium text-slate-800">{v}</dd>
    </div>
  );
}
