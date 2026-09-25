import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";

export const dynamic = "force-dynamic";

/**
 * GET /api/permissions(?q=raj) — super admin (ADMIN) only: employee picker for the
 * on-device permission toggles. Matches name or code; ACTIVE staff, max 40.
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role !== "ADMIN") return jsonError("Super admin only.", 403);

  const q = (req.nextUrl.searchParams.get("q") ?? "").trim();
  const employees = await db.employee.findMany({
    where: {
      companyId: me.companyId,
      status: "ACTIVE",
      ...(q
        ? {
            OR: [
              { firstName: { contains: q, mode: "insensitive" } },
              { lastName: { contains: q, mode: "insensitive" } },
              { code: { contains: q, mode: "insensitive" } },
            ],
          }
        : {}),
    },
    select: {
      id: true,
      code: true,
      firstName: true,
      lastName: true,
      photoExt: true,
      department: { select: { name: true } },
      permission: { select: { canPunch: true, canApplyLeave: true, canGatePass: true, canSwapShift: true, canSocialPost: true, canViewPayslip: true } },
    },
    orderBy: { code: "asc" },
    take: 40,
  });

  return NextResponse.json({
    employees: employees.map((e) => {
      const p = e.permission;
      const off = p ? Object.values(p).filter((v) => v === false).length : 0;
      return {
        id: e.id,
        code: e.code,
        name: `${e.firstName} ${e.lastName}`.trim(),
        dept: e.department?.name ?? null,
        photo: e.photoExt ? `/api/photo/${e.id}` : null,
        offCount: off, // how many features are switched OFF
      };
    }),
  });
}
