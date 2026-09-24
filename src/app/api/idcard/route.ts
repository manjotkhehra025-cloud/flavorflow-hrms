import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

/** GET /api/idcard — my digital badge details (P4 mobile ID card). */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  const { db } = await import("@/lib/db");
  const emp = await db.employee.findFirst({
    where: { id: me.employeeId, companyId: me.companyId },
    include: { department: true, designation: true, shift: true, company: { select: { name: true, code: true } } },
  });
  if (!emp) return NextResponse.json({ error: "Employee not found" }, { status: 404 });

  return NextResponse.json({
    name: `${emp.firstName} ${emp.lastName}`,
    code: emp.code,
    department: emp.department?.name ?? null,
    designation: emp.designation?.title ?? null,
    bloodGroup: emp.bloodGroup ?? null,
    phone: emp.phone ?? null,
    joined: emp.joinDate,
    category: emp.category,
    company: emp.company.name,
    shift: emp.shift ? { name: emp.shift.name, startTime: emp.shift.startTime, durationH: emp.shift.durationH } : null,
    photoUrl: `/api/photo/${emp.id}`,
    verifyUrl: `/verify/${encodeURIComponent(emp.code)}`, // original web QR target (share/print fallback)
  });
}
