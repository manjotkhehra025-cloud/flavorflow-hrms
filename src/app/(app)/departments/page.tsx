import { Pa } from "@/components/Pa";
import { pht } from "@/lib/i18n";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { Card, PageHeader, inputCls, btnBrand } from "@/components/ui";
import {
  addDepartmentAction,
  deleteDepartmentAction,
  addDesignationAction,
  deleteDesignationAction,
  seedGdStructureAction,
} from "@/actions/departments";
import { DepartmentEditor } from "./DepartmentEditor";
import { DesignationEditor } from "./DesignationEditor";

export const dynamic = "force-dynamic";

export default async function DepartmentsPage() {
  const me = await requireStaff();
  const [departments, designations, counts] = await Promise.all([
    db.department.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" }, include: { subDepartments: true } }),
    db.designation.findMany({ where: { companyId: me.companyId }, orderBy: { title: "asc" } }),
    db.employee.groupBy({ by: ["departmentId"], where: { companyId: me.companyId }, _count: true }),
  ]);
  const countByDept = new Map(counts.map((c) => [c.departmentId, c._count]));
  const topLevel = departments.filter((d) => !d.parentId);
  const subOf = (pid: string) => departments.filter((d) => d.parentId === pid);
  const deptName = (id: string | null) => departments.find((d) => d.id === id)?.name ?? null;
  const isAdmin = me.role === "ADMIN";

  const officialDesigs = designations.filter((d) => d.category !== "YELLOW_CARD");
  const ycDesigs = designations.filter((d) => d.category === "YELLOW_CARD");

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <PageHeader title={<Pa>Org Structure</Pa>} subtitle={<Pa>Departments, sub-departments & designations — add, edit, remove anytime.</Pa>} />
        <form action={seedGdStructureAction}>
          <button className={`${btnBrand} text-xs`}>{<Pa>Seed G.D. Foods structure</Pa>}</button>
        </form>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* ───── Departments tree ───── */}
        <Card className="p-5">
          <h3 className="mb-3 text-sm font-bold text-slate-900">{<Pa>Departments</Pa>}</h3>
          <ul className="mb-4 space-y-1.5">
            {topLevel.map((d) => (
              <li key={d.id}>
                <DepartmentRow
                  id={d.id}
                  name={d.name}
                  parentId={null}
                  people={countByDept.get(d.id) ?? 0}
                  isAdmin={isAdmin}
                  departments={topLevel.map((t) => ({ id: t.id, name: t.name }))}
                />
                {subOf(d.id).map((s2) => (
                  <div key={s2.id} className="ml-6 mt-1.5 border-l-2 border-emerald-200 pl-3">
                    <DepartmentRow
                      id={s2.id}
                      name={s2.name}
                      parentId={d.id}
                      people={countByDept.get(s2.id) ?? 0}
                      sub
                      isAdmin={isAdmin}
                      departments={topLevel.map((t) => ({ id: t.id, name: t.name }))}
                    />
                  </div>
                ))}
              </li>
            ))}
            {departments.length === 0 && <li className="py-2 text-sm text-slate-500"><Pa>None yet — seed or add one below.</Pa></li>}
          </ul>
          <form action={addDepartmentAction} className="flex flex-wrap gap-2">
            <input name="name" required placeholder={await pht("New department name…")} className={inputCls + " min-w-0 flex-1"} />
            <select name="parentId" defaultValue="" className={inputCls + " !w-auto"} aria-label="Parent (optional)">
              <option value=""><Pa>Top level</Pa></option>
              {topLevel.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
            <button className={btnBrand}>{<Pa>Add</Pa>}</button>
          </form>
          <p className="mt-2 text-[11px] text-slate-400"><Pa>Pick a parent to create a sub-department (e.g. Lab under Quality).</Pa></p>
        </Card>

        {/* ───── Designations ───── */}
        <div className="space-y-6">
          <Card className="p-5">
            <h3 className="mb-3 text-sm font-bold text-slate-900">{<Pa>Official designations</Pa>}</h3>
            <ul className="divide-y divide-slate-100">
              {officialDesigs.map((d) => (
                <DesignationRow key={d.id} id={d.id} title={d.title} category={d.category} deptName={deptName(d.departmentId)} isAdmin={isAdmin} departments={departments.map((t) => ({ id: t.id, name: t.name }))} />
              ))}
              {officialDesigs.length === 0 && <li className="py-2 text-sm text-slate-500"><Pa>None yet.</Pa></li>}
            </ul>
          </Card>
          <Card className="p-5">
            <h3 className="mb-3 text-sm font-bold text-slate-900">{<Pa>Yellow Card designations</Pa>}</h3>
            <ul className="divide-y divide-slate-100">
              {ycDesigs.map((d) => (
                <DesignationRow key={d.id} id={d.id} title={d.title} category={d.category} deptName={deptName(d.departmentId)} isAdmin={isAdmin} departments={departments.map((t) => ({ id: t.id, name: t.name }))} />
              ))}
              {ycDesigs.length === 0 && <li className="py-2 text-sm text-slate-500"><Pa>None yet.</Pa></li>}
            </ul>
          </Card>
          <Card className="p-5">
            <h3 className="mb-3 text-sm font-bold text-slate-900">{<Pa>Add designation</Pa>}</h3>
            <form action={addDesignationAction} className="flex flex-wrap gap-2">
              <input name="title" required placeholder={await pht("Title…")} className={inputCls + " min-w-0 flex-1"} />
              <select name="category" defaultValue="OFFICIAL" className={inputCls + " !w-auto"}>
                <option value="OFFICIAL"><Pa>Official</Pa></option>
                <option value="YELLOW_CARD"><Pa>Yellow Card</Pa></option>
                <option value="BOTH"><Pa>Both</Pa></option>
              </select>
              <select name="departmentId" defaultValue="" className={inputCls + " !w-auto"} aria-label="Home dept (optional)">
                <option value=""><Pa>No dept</Pa></option>
                {departments.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
              </select>
              <button className={btnBrand}>{<Pa>Add</Pa>}</button>
            </form>
          </Card>
        </div>
      </div>
    </div>
  );
}

function DepartmentRow({ id, name, parentId, people, sub = false, isAdmin, departments }: {
  id: string; name: string; parentId: string | null; people: number; sub?: boolean; isAdmin: boolean;
  departments: { id: string; name: string }[];
}) {
  return (
    <div className={`flex items-center justify-between rounded-xl px-3.5 py-2.5 ${sub ? "bg-white ring-1 ring-emerald-100" : "bg-slate-50"}`}>
      <div className="flex min-w-0 flex-wrap items-baseline gap-x-2">
        <span className="text-sm font-bold text-slate-800">{name}</span>
        <span className="shrink-0 whitespace-nowrap text-[11px] text-slate-400">{people} {people === 1 ? <Pa>person</Pa> : <Pa>people</Pa>}</span>
      </div>
      <div className="relative flex items-center gap-1.5">
        <DepartmentEditor id={id} name={name} parentId={parentId} departments={departments.filter((d) => d.id !== id)} />
        {isAdmin && (
          <form action={deleteDepartmentAction.bind(null, id)}>
            <button className="rounded-lg px-2.5 py-1.5 text-xs font-semibold text-red-500 hover:bg-red-50"><Pa>Delete</Pa></button>
          </form>
        )}
      </div>
    </div>
  );
}

function DesignationRow({ id, title, category, deptName, isAdmin, departments }: {
  id: string; title: string; category: string; deptName: string | null; isAdmin: boolean;
  departments: { id: string; name: string }[];
}) {
  return (
    <li className="flex items-center justify-between py-2.5 text-sm">
      <div className="min-w-0">
        <span className="font-medium text-slate-800">{title}</span>
        <span className="ml-2 flex-wrap gap-1 text-[10px]">
          <span className={`rounded-full px-1.5 py-0.5 font-extrabold ${category === "YELLOW_CARD" ? "bg-amber-100 text-amber-700" : category === "OFFICIAL" ? "bg-slate-200 text-slate-600" : "bg-emerald-100 text-emerald-700"}`}>
            {category === "YELLOW_CARD" ? <Pa>Yellow Card</Pa> : category === "OFFICIAL" ? <Pa>Official</Pa> : <Pa>Both</Pa>}
          </span>
          {deptName && <span className="ml-1 rounded bg-slate-100 px-1.5 py-0.5 font-semibold text-slate-500">{deptName}</span>}
        </span>
      </div>
      <div className="relative flex items-center gap-1.5">
        <DesignationEditor id={id} title={title} category={category} departments={departments} />
        {isAdmin && (
          <form action={deleteDesignationAction.bind(null, id)}>
            <button className="rounded-lg px-2.5 py-1.5 text-xs font-semibold text-red-500 hover:bg-red-50"><Pa>Delete</Pa></button>
          </form>
        )}
      </div>
    </li>
  );
}
