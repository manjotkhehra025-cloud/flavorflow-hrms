import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { getPerms } from "@/lib/permissions";
import { approverScope } from "@/lib/approve-routing";

/**
 * GET /api/auth/me — session claims + fresh flags the app needs on boot:
 * mustChangePassword (force /set-password), the 6 permission booleans
 * (hide/show features), language, and whether the user can open Approvals
 * (ADMIN/HR or a routed department head).
 */
export async function GET(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const user = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const fresh = await db.user.findUnique({
    where: { id: user.id },
    select: { mustChangePassword: true, locale: true, isActive: true },
  });
  if (!fresh?.isActive) return NextResponse.json({ error: "Account disabled" }, { status: 403 });

  const scope = await approverScope(user);
  const perms = await getPerms(user.employeeId);

  return NextResponse.json({
    user: {
      ...user,
      locale: fresh.locale,
      mustChangePassword: fresh.mustChangePassword,
      canApprove: scope !== null,
      approveScope: scope, // "ALL" | "A" | "B" (null when neither)
      perms,
    },
  });
}
