import { pht } from "@/lib/i18n";
import { Pa } from "@/components/Pa";
import Link from "next/link";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { fmtDate, initials, cx } from "@/lib/utils";
import { Card, PageHeader, Badge, btnBrand, inputCls } from "@/components/ui";
import { AdminResetButton } from "@/components/PasswordCards";

export const dynamic = "force-dynamic";

export default async function EmployeesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string }>;
}) {
  const me = await requireStaff();
  const { q, status } = await searchParams;

  const employees = await db.employee.findMany({
    where: {
      companyId: me.companyId,
      status: status === "INACTIVE" ? "INACTIVE" : "ACTIVE",
      ...(q
        ? {
            OR: [
              { firstName: { contains: q, mode: "insensitive" } },
              { lastName: { contains: q, mode: "insensitive" } },
              { code: { contains: q, mode: "insensitive" } },
              { email: { contains: q, mode: "insensitive" } },
            ],
          }
        : {}),
    },
    include: { department: true, designation: true, users: { select: { id: true, role: true } } },
    orderBy: [{ firstName: "asc" }],
    take: 100,
  });

  return (
    <div>
      <PageHeader
        title={<Pa>Employees</Pa>}
        subtitle={`${employees.length} ${status === "INACTIVE" ? "inactive" : "active"} people`}
        actions={
          <Link href="/employees/new" className={btnBrand}>
            + Add employee
          </Link>
        }
      />

      <Card className="mb-4 p-3">
        <form className="flex flex-wrap items-center gap-2" method="GET" action="/employees">
          <input
            name="q"
            defaultValue={q ?? ""}
            placeholder={await pht("Search name, code or email…")}
            className={cx(inputCls, "max-w-xs")}
          />
          <select name="status" defaultValue={status ?? "ACTIVE"} className={cx(inputCls, "w-auto")}>
            <option value="ACTIVE">{<Pa>Active</Pa>}</option>
            <option value="INACTIVE">{<Pa>Inactive</Pa>}</option>
          </select>
          <button className={btnBrand}>{<Pa>Search</Pa>}</button>
        </form>
      </Card>

      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50/80">
                <th className="th">{<Pa>Employee</Pa>}</th>
                <th className="th">{<Pa>Code</Pa>}</th>
                <th className="th">{<Pa>Department</Pa>}</th>
                <th className="th">{<Pa>Designation</Pa>}</th>
                <th className="th">{<Pa>Joined</Pa>}</th>
                <th className="th">{<Pa>Login</Pa>}</th>
                <th className="th">{<Pa>Status</Pa>}</th>
              </tr>
            </thead>
            <tbody>
              {employees.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-5 py-10 text-center text-slate-500">
                    No employees found. <Link href="/employees/new" className="text-amber-600 hover:underline">{<Pa>Add one</Pa>}</Link>.
                  </td>
                </tr>
              )}
              {employees.map((e) => (
                <tr key={e.id} className="border-b border-slate-50 transition-colors last:border-0 hover:bg-amber-50/40">
                  <td className="px-5 py-3">
                    <Link href={`/employees/${e.id}`} className="flex items-center gap-3">
                      <span className="flex h-9 w-9 items-center justify-center rounded-full bg-slate-900 text-xs font-bold text-amber-400 ring-2 ring-amber-400/20">
                        {initials(`${e.firstName} ${e.lastName}`)}
                      </span>
                      <span>
                        <span className="block font-medium text-slate-900">
                          {e.firstName} {e.lastName}
                        </span>
                        <span className="block text-xs text-slate-500">{e.email ?? e.phone ?? ""}</span>
                      </span>
                    </Link>
                  </td>
                  <td className="px-5 py-3 font-mono text-xs text-slate-600">{e.code}</td>
                  <td className="px-5 py-3 text-slate-600">{e.department?.name ?? "—"}</td>
                  <td className="px-5 py-3 text-slate-600">{e.designation?.title ?? "—"}</td>
                  <td className="px-5 py-3 text-slate-600">{fmtDate(e.joinDate)}</td>
                  <td className="px-5 py-3">
                    {e.users.length > 0 ? (
                      <span className="flex items-center gap-1.5">
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[11px] font-bold text-emerald-700 ring-1 ring-emerald-200">
                          ✓ {e.users[0].role === "EMPLOYEE" ? "Login" : e.users[0].role}
                        </span>
                        {me.role === "ADMIN" && <AdminResetButton userId={e.users[0].id} name={e.firstName} compact />}
                      </span>
                    ) : (
                      <span className="text-xs text-slate-300">—</span>
                    )}
                  </td>
                  <td className="px-5 py-3">
                    <Badge tone={e.status === "ACTIVE" ? "green" : "slate"}>{e.status}</Badge>
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
