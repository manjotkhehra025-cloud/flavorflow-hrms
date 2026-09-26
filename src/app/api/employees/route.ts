import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";

export const dynamic = "force-dynamic";

/**
 * GET /api/employees?q=&status=ACTIVE|INACTIVE&take=100
 * Staff only — same filter as web /employees (parity row 13).
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role === "EMPLOYEE") return jsonError("Only HR / admin can view employees.", 403);

  const q = (req.nextUrl.searchParams.get("q") ?? "").trim();
  const statusParam = (req.nextUrl.searchParams.get("status") ?? "ACTIVE").toUpperCase();
  const status = statusParam === "INACTIVE" ? "INACTIVE" : "ACTIVE";
  const takeRaw = Number(req.nextUrl.searchParams.get("take") ?? "100");
  const take = Number.isFinite(takeRaw) ? Math.min(Math.max(takeRaw, 1), 150) : 100;

  const employees = await db.employee.findMany({
    where: {
      companyId: me.companyId,
      status: status as any,
      ...(q
        ? {
            OR: [
              { firstName: { contains: q, mode: "insensitive" } },
              { lastName: { contains: q, mode: "insensitive" } },
              { code: { contains: q, mode: "insensitive" } },
              { email: { contains: q, mode: "insensitive" } },
              { phone: { contains: q, mode: "insensitive" } },
            ],
          }
        : {}),
    },
    include: {
      department: { select: { name: true } },
      designation: { select: { title: true } },
      shift: { select: { name: true, startTime: true } },
      users: { select: { id: true, role: true, email: true } },
    },
    orderBy: [{ firstName: "asc" }],
    take,
  });

  return NextResponse.json({
    employees: employees.map((e: any) => ({
      id: e.id,
      code: e.code,
      name: `${e.firstName} ${e.lastName}`.trim(),
      firstName: e.firstName,
      lastName: e.lastName,
      email: e.email ?? null,
      phone: e.phone ?? null,
      dept: e.department?.name ?? null,
      designation: e.designation?.title ?? null,
      shift: e.shift ? `${e.shift.name} ${e.shift.startTime}` : null,
      photo: e.photoExt ? `/api/photo/${e.id}` : null,
      status: e.status,
      category: e.category,
      joinDate: e.joinDate.toISOString().slice(0, 10),
      hasLogin: e.users.length > 0,
      loginRole: e.users[0]?.role ?? null,
      loginEmail: e.users[0]?.email ?? null,
    })),
    count: employees.length,
    status,
  });
}
