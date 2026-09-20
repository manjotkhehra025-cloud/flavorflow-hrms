import { db } from "./db";

/** Default org data created at /setup: departments, designations, leave types. */
export async function seedOrgDefaults(companyId: string) {
  await db.department.createMany({
    data: [
      { companyId, name: "Management" },
      { companyId, name: "Operations" },
      { companyId, name: "Kitchen" },
      { companyId, name: "Delivery" },
      { companyId, name: "Sales & Marketing" },
    ],
    skipDuplicates: true,
  });

  await db.designation.createMany({
    data: [
      { companyId, title: "Founder / Director" },
      { companyId, title: "Manager" },
      { companyId, title: "Team Lead" },
      { companyId, title: "Executive" },
      { companyId, title: "Trainee" },
    ],
    skipDuplicates: true,
  });

  await db.leaveType.createMany({
    data: [
      { companyId, name: "Casual Leave", daysPerYear: 12 },
      { companyId, name: "Sick Leave", daysPerYear: 12 },
      { companyId, name: "Earned Leave", daysPerYear: 15 },
      { companyId, name: "Unpaid Leave", daysPerYear: 0 },
    ],
    skipDuplicates: true,
  });
}

/** Next employee code like FF-007 within a company. */
export async function nextEmployeeCode(companyId: string, companyCode: string) {
  const count = await db.employee.count({ where: { companyId } });
  return `${companyCode}-${String(count + 1).padStart(3, "0")}`;
}
