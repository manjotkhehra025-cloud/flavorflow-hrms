import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { PageHeader, Card } from "@/components/ui";
import { NewEmployeeForm } from "./NewEmployeeForm";

export const dynamic = "force-dynamic";

export default async function NewEmployeePage() {
  const me = await requireStaff();
  const [departments, designations, shifts] = await Promise.all([
    db.department.findMany({ where: { companyId: me.companyId }, orderBy: { name: "asc" } }),
    db.designation.findMany({ where: { companyId: me.companyId }, orderBy: { title: "asc" } }),
    db.shift.findMany({ where: { companyId: me.companyId }, orderBy: { startTime: "asc" } }),
  ]);

  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader title="Add employee" subtitle="Fill the basics — details can be enriched later." />
      <Card className="p-6">
        <NewEmployeeForm departments={departments} designations={designations} shifts={shifts} />
      </Card>
    </div>
  );
}
