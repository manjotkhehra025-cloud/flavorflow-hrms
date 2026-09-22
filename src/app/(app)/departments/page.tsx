import { pht } from "@/lib/i18n";
import { Pa } from "@/components/Pa";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Card, PageHeader, inputCls, btnBrand } from "@/components/ui";
import {
  addDepartmentAction,
  deleteDepartmentAction,
  addDesignationAction,
  deleteDesignationAction,
} from "@/actions/departments";

export const dynamic = "force-dynamic";

export default async function DepartmentsPage() {
  const me = await requireStaff();
  const [departments, designations, counts] = await Promise.all([
    db.department.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" } }),
    db.designation.findMany({ where: { companyId: me.companyId }, orderBy: { title: "asc" } }),
    db.employee.groupBy({ by: ["departmentId"], where: { companyId: me.companyId }, _count: true }),
  ]);
  const countByDept = new Map(counts.map((c) => [c.departmentId, c._count]));

  return (
    <div>
      <PageHeader title={<Pa>Departments & Designations</Pa>} subtitle={<Pa>Your organisation's structure.</Pa>} />
      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="p-5">
          <h3 className="mb-3 text-sm font-semibold text-slate-900">{<Pa>Departments</Pa>}</h3>
          <ul className="mb-4 divide-y divide-slate-100">
            {departments.map((d) => (
              <li key={d.id} className="flex items-center justify-between py-2 text-sm">
                <span className="font-medium text-slate-700">{d.name}</span>
                <span className="flex items-center gap-3">
                  <span className="text-xs text-slate-500">{countByDept.get(d.id) ?? 0} people</span>
                  {me.role === "ADMIN" && (
                    <form action={deleteDepartmentAction.bind(null, d.id)}>
                      <button className="text-xs text-red-500 hover:underline">{<Pa>Delete</Pa>}</button>
                    </form>
                  )}
                </span>
              </li>
            ))}
            {departments.length === 0 && <li className="py-2 text-sm text-slate-500">{<Pa>None yet.</Pa>}</li>}
          </ul>
          <form action={addDepartmentAction} className="flex gap-2">
            <input name="name" required placeholder={await pht("New department…")} className={inputCls} />
            <button className={btnBrand}>{<Pa>Add</Pa>}</button>
          </form>
        </Card>

        <Card className="p-5">
          <h3 className="mb-3 text-sm font-semibold text-slate-900">{<Pa>Designations</Pa>}</h3>
          <ul className="mb-4 divide-y divide-slate-100">
            {designations.map((d) => (
              <li key={d.id} className="flex items-center justify-between py-2 text-sm">
                <span className="font-medium text-slate-700">{d.title}</span>
                {me.role === "ADMIN" && (
                  <form action={deleteDesignationAction.bind(null, d.id)}>
                    <button className="text-xs text-red-500 hover:underline">{<Pa>Delete</Pa>}</button>
                  </form>
                )}
              </li>
            ))}
            {designations.length === 0 && <li className="py-2 text-sm text-slate-500">{<Pa>None yet.</Pa>}</li>}
          </ul>
          <form action={addDesignationAction} className="flex gap-2">
            <input name="title" required placeholder={await pht("New designation…")} className={inputCls} />
            <button className={btnBrand}>{<Pa>Add</Pa>}</button>
          </form>
        </Card>
      </div>
    </div>
  );
}
