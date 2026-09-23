import { Pa } from "@/components/Pa";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { PageHeader, Card } from "@/components/ui";
import { NewEmployeeForm } from "./NewEmployeeForm";

export const dynamic = "force-dynamic";

export default async function NewEmployeePage() {
  const me = await requireStaff();
  const [departmentsAll, designationsAll, shifts] = await Promise.all([
    db.department.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" } }),
    db.designation.findMany({ where: { companyId: me.companyId }, orderBy: { title: "asc" } }),
    db.shift.findMany({ where: { companyId: me.companyId }, orderBy: { startTime: "asc" } }),
  ]);
  // Hierarchy-aware labels: "Quality › Lab"
  const labelOf = (d: (typeof departmentsAll)[number]) =>
    d.parentId ? `${departmentsAll.find((p) => p.id === d.parentId)?.name ?? ""} › ${d.name}` : d.name;
  const departments = [...departmentsAll]
    .sort((a, b) => (labelOf(a) < labelOf(b) ? -1 : 1))
    .map((d) => ({ ...d, name: labelOf(d) }));
  const designations = designationsAll.map((d) => ({ id: d.id, title: d.title, category: d.category }));

  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader title={<Pa>Add employee</Pa>} subtitle={<Pa>Fill the basics — details can be enriched later.</Pa>} />
      <Card className="p-6">
        <NewEmployeeForm departments={departments} designations={designations} shifts={shifts} />
      </Card>
    </div>
  );
}
