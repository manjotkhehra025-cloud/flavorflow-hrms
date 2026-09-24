import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";
const db = new PrismaClient();
(async () => {
  const company = await db.company.findFirstOrThrow();
  const dsg = async (title: string) => (await db.designation.upsert({ where: { companyId_title: { companyId: company.id, title } }, update: {}, create: { companyId: company.id, title } })).id;
  const dep = async (name: string) => (await db.department.upsert({ where: { companyId_name: { companyId: company.id, name } }, update: {}, create: { companyId: company.id, name } })).id;
  const smD = await dsg("Senior Manager");
  const agmD = await dsg("Assistant General Manager");
  const opD = await dsg("Operator");
  const prod = await dep("Production");
  const mech = await dep("Mechanical");
  const hash = await bcrypt.hash("Test@1234", 10);
  const mk = async (code: string, fn: string, ln: string, depId: string, dsgId: string, email: string) => {
    const emp = await db.employee.upsert({
      where: { companyId_code: { companyId: company.id, code } },
      update: { departmentId: depId, designationId: dsgId },
      create: { companyId: company.id, code, firstName: fn, lastName: ln, departmentId: depId, designationId: dsgId, joinDate: new Date("2024-01-01"), category: "OFFICIAL" },
    });
    await db.user.upsert({
      where: { email },
      update: { employeeId: emp.id },
      create: { companyId: company.id, employeeId: emp.id, name: `${fn} ${ln}`, email, passwordHash: hash, role: "EMPLOYEE" },
    });
    return emp;
  };
  await mk("SM01", "Sukhdev", "SeniorManager", prod, smD, "sm@test.in");
  await mk("AGM1", "Ranjit", "AGM", mech, agmD, "agm@test.in");
  const op1 = await mk("OP01", "Harbhajan", "Op", prod, opD, "op1@test.in");
  const op2 = await mk("OP02", "Sukhchain", "Op", mech, opD, "op2@test.in");
  let lt = await db.leaveType.findFirst({ where: { companyId: company.id } });
  if (!lt) lt = await db.leaveType.create({ data: { companyId: company.id, name: "Earned Leave", daysPerYear: 15 } });
  await db.leaveRequest.create({ data: { companyId: company.id, employeeId: op1.id, leaveTypeId: lt.id, fromDate: new Date("2026-10-01"), toDate: new Date("2026-10-02"), days: 2, reason: "route A test" } });
  await db.punchRequest.create({ data: { companyId: company.id, employeeId: op1.id, type: "MANUAL_IN", date: new Date("2026-09-24"), time: "09:00", reason: "route A punch test" } });
  await db.gatePass.create({ data: { companyId: company.id, employeeId: op2.id, date: new Date("2026-09-24"), exitAt: "14:00", returnAt: "15:00", reason: "route B gate test" } });
  await db.leaveRequest.create({ data: { companyId: company.id, employeeId: op2.id, leaveTypeId: lt.id, fromDate: new Date("2026-10-05"), toDate: new Date("2026-10-05"), days: 1, reason: "route B test" } });
  console.log("ROUTE-FIXTURES-OK");
})().finally(() => db.$disconnect());
