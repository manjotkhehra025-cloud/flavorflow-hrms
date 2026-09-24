/**
 * Demo fixture for the dev sandbox (op1/op2/logins + geo-fence + leave types).
 * SAFETY: refuses to run against any database that isn't 127.0.0.1/localhost,
 * so it can never touch production. Used by scripts/sandbox-restore.sh.
 */
import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const url = process.env.DATABASE_URL ?? "";
if (!/127\.0\.0\.1|localhost/.test(url)) {
  console.error("demo-fixture: refusing — DATABASE_URL is not localhost:", url.replace(/\/\/.*@/, "//***@"));
  process.exit(1);
}

const db = new PrismaClient();
(async () => {
  const company = await db.company.findFirstOrThrow();
  await db.company.update({ where: { id: company.id }, data: { geofenceEnabled: true, geoLat: 31.634, geoLng: 74.8723, geoRadius: 400 } });
  const dept = (await db.department.findFirst({ where: { companyId: company.id, name: "Operations" } })) ??
    (await db.department.create({ data: { companyId: company.id, name: "Operations" } }));
  const desig = (await db.designation.findFirst({ where: { companyId: company.id, title: "Operator" } })) ??
    (await db.designation.create({ data: { companyId: company.id, title: "Operator", category: "BOTH" } }));
  const shift = (await db.shift.findFirst({ where: { companyId: company.id } })) ??
    (await db.shift.create({ data: { companyId: company.id, name: "General Shift", startTime: "09:00", durationH: 8.5 } }));
  for (const [name, days] of [["Casual Leave", 9], ["Sick Leave", 8], ["Earned Leave", 15]] as const) {
    await db.leaveType.upsert({ where: { companyId_name: { companyId: company.id, name } }, update: {}, create: { companyId: company.id, name, daysPerYear: days } });
  }
  const hash = await bcrypt.hash("Test@1234", 10);
  const emp = await db.employee.upsert({
    where: { companyId_code: { companyId: company.id, code: "OP1" } },
    update: { departmentId: dept.id, designationId: desig.id, shiftId: shift.id, bloodGroup: "O+", phone: "+91 98765 43210" },
    create: { companyId: company.id, code: "OP1", firstName: "Raj", lastName: "Gill", departmentId: dept.id, designationId: desig.id, shiftId: shift.id, email: "op1@test.in", joinDate: new Date("2025-01-01"), bloodGroup: "O+", phone: "+91 98765 43210" },
  });
  const emp2 = await db.employee.upsert({
    where: { companyId_code: { companyId: company.id, code: "OP2" } },
    update: {},
    create: { companyId: company.id, code: "OP2", firstName: "Harpreet", lastName: "Kaur", departmentId: dept.id, joinDate: new Date("2025-03-01") },
  });
  await db.user.upsert({
    where: { email: "op1@test.in" },
    update: { isActive: true, employeeId: emp.id, passwordHash: hash, name: "Raj Gill", companyId: company.id },
    create: { companyId: company.id, email: "op1@test.in", name: "Raj Gill", role: "EMPLOYEE", passwordHash: hash, employeeId: emp.id },
  });
  await db.user.upsert({
    where: { email: "op2@test.in" },
    update: { isActive: true, employeeId: emp2.id, name: "Harpreet Kaur", companyId: company.id },
    create: { companyId: company.id, email: "op2@test.in", name: "Harpreet Kaur", role: "EMPLOYEE", passwordHash: hash, employeeId: emp2.id },
  });
  for (const e of [emp, emp2]) {
    const perm = await db.employeePermission.findUnique({ where: { employeeId: e.id } });
    if (perm) await db.employeePermission.update({ where: { employeeId: e.id }, data: { canPunch: true } });
    else await db.employeePermission.create({ data: { companyId: company.id, employeeId: e.id, canPunch: true } });
  }
  console.log("demo-fixture ✓ (op1@test.in / op2@test.in — Test@1234, fence 400m)");
  await db.$disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
