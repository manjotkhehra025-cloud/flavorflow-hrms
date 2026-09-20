import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { fmtDate, initials, fmtTime, todayDate } from "@/lib/utils";
import { Card, PageHeader, Badge, btnGhost } from "@/components/ui";
import { updateEmployeeStatusAction, deleteEmployeeAction } from "@/actions/employees";

export const dynamic = "force-dynamic";

export default async function EmployeeDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireStaff();
  const { id } = await params;

  const employee = await db.employee.findFirst({
    where: { id, companyId: me.companyId },
    include: {
      department: true,
      designation: true,
      users: { select: { email: true, role: true, isActive: true } },
    },
  });
  if (!employee) notFound();

  const monthStart = new Date(Date.UTC(todayDate().getUTCFullYear(), todayDate().getUTCMonth(), 1));
  const [attendance, leaves] = await Promise.all([
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
  ]);

  const bindToggle = updateEmployeeStatusAction.bind(
    null,
    employee.id,
    employee.status === "ACTIVE" ? "INACTIVE" : "ACTIVE"
  );

  return (
    <div>
      <PageHeader
        title={`${employee.firstName} ${employee.lastName}`}
        subtitle={`${employee.code} · ${employee.designation?.title ?? "No designation"}`}
        actions={
          <div className="flex gap-2">
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
            <div className="flex h-20 w-20 items-center justify-center rounded-full bg-slate-900 text-2xl font-black text-amber-400">
              {initials(`${employee.firstName} ${employee.lastName}`)}
            </div>
            <h2 className="mt-3 text-lg font-bold text-slate-900">
              {employee.firstName} {employee.lastName}
            </h2>
            <Badge tone={employee.status === "ACTIVE" ? "green" : "slate"}>{employee.status}</Badge>
          </div>
          <dl className="mt-6 space-y-3 text-sm">
            <Row k="Email" v={employee.email ?? "—"} />
            <Row k="Phone" v={employee.phone ?? "—"} />
            <Row k="Department" v={employee.department?.name ?? "—"} />
            <Row k="Designation" v={employee.designation?.title ?? "—"} />
            <Row k="Joined" v={fmtDate(employee.joinDate)} />
            <Row k="Gender" v={employee.gender ?? "—"} />
            <Row k="Address" v={employee.address ?? "—"} />
            <Row
              k="Login"
              v={employee.users[0] ? `${employee.users[0].email} (${employee.users[0].role})` : "No account"}
            />
          </dl>
        </Card>

        <Card className="p-6 lg:col-span-2">
          <h3 className="mb-4 text-sm font-semibold text-slate-900">This month's attendance</h3>
          {attendance.length === 0 ? (
            <p className="text-sm text-slate-500">No attendance records yet this month.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                    <th className="py-2 pr-4">Date</th>
                    <th className="py-2 pr-4">In</th>
                    <th className="py-2 pr-4">Out</th>
                    <th className="py-2">Status</th>
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

          <h3 className="mb-4 mt-8 text-sm font-semibold text-slate-900">Recent leave requests</h3>
          {leaves.length === 0 ? (
            <p className="text-sm text-slate-500">No leave requests yet.</p>
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
            <Link href="/employees" className="text-sm text-slate-500 hover:underline">← Back to employees</Link>
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
