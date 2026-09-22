const bcrypt = require('bcryptjs');
const { PrismaClient } = require('@prisma/client');
const db = new PrismaClient();
(async () => {
  const h = await bcrypt.hash('Test@1234', 10);
  const cid = 'co-gdf';
  await db.company.upsert({ where: { id: cid }, update: {}, create: { id: cid, name: 'G.D. Foods', code: 'GDF' }});
  await db.department.create({ data: { companyId: cid, name: 'Kitchen' } }).catch(() => {});
  const dep = await db.department.findFirst({ where: { companyId: cid } });
  for (const [email, name, role] of [['manjot@gdf.in', 'Manjot Singh', 'ADMIN'], ['hr@gdf.in', 'HR Manager', 'HR']]) {
    await db.user.upsert({ where: { email }, update: {}, create: { companyId: cid, email, name, passwordHash: h, role } });
  }
  await db.employee.upsert({ where: { companyId_code: { companyId: cid, code: 'GDF-101' } }, update: {}, create: { companyId: cid, code: 'GDF-101', firstName: 'Nirmala', lastName: 'Kaur', gender: 'Female', joinDate: new Date('2025-06-01'), departmentId: dep?.id, category: 'OFFICIAL', weeklyOff: 0 } });
  await db.employee.upsert({ where: { companyId_code: { companyId: cid, code: 'GDF-102' } }, update: {}, create: { companyId: cid, code: 'GDF-102', firstName: 'Baljit', lastName: 'Kaur', gender: 'Female', joinDate: new Date('2026-09-01'), departmentId: dep?.id, category: 'YELLOW_CARD', weeklyOff: 0 } });
  await db.shift.create({ data: { companyId: cid, name: 'General Day', startTime: '08:00', durationH: 9 } }).catch(() => {});
  const sh = await db.shift.findFirst({ where: { companyId: cid } });
  if (sh) await db.employee.updateMany({ where: { companyId: cid }, data: { shiftId: sh.id } });
  const emp = await db.employee.findFirst({ where: { code: 'GDF-102' } });
  await db.user.upsert({ where: { email: 'baljit@gdf.in' }, update: { employeeId: emp.id }, create: { companyId: cid, email: 'baljit@gdf.in', name: 'Baljit Kaur', passwordHash: h, role: 'EMPLOYEE', employeeId: emp.id } });
  console.log('seed OK', emp.id);
  await db.$disconnect();
})().catch((e) => { console.error(e.message); process.exit(1); });
