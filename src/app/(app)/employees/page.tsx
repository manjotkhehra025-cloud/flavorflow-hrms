import Link from "next/link";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { fmtDate, initials, cx } from "@/lib/utils";
import { Card, PageHeader, Badge, btnBrand, inputCls } from "@/components/ui";

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
    include: { department: true, designation: true },
    orderBy: [{ firstName: "asc" }],
    take: 100,
  });

  return (
    <div>
      <PageHeader
        title="Employees"
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
            placeholder="Search name, code or email…"
            className={cx(inputCls, "max-w-xs")}
          />
          <select name="status" defaultValue={status ?? "ACTIVE"} className={cx(inputCls, "w-auto")}>
            <option value="ACTIVE">Active</option>
            <option value="INACTIVE">Inactive</option>
          </select>
          <button className={btnBrand}>Search</button>
        </form>
      </Card>

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-xs uppercase tracking-wide text-slate-500">
                <th className="px-5 py-3">Employee</th>
                <th className="px-5 py-3">Code</th>
                <th className="px-5 py-3">Department</th>
                <th className="px-5 py-3">Designation</th>
                <th className="px-5 py-3">Joined</th>
                <th className="px-5 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {employees.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-5 py-10 text-center text-slate-500">
                    No employees found. <Link href="/employees/new" className="text-amber-600 hover:underline">Add one</Link>.
                  </td>
                </tr>
              )}
              {employees.map((e) => (
                <tr key={e.id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                  <td className="px-5 py-3">
                    <Link href={`/employees/${e.id}`} className="flex items-center gap-3">
                      <span className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-xs font-bold text-amber-400">
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
