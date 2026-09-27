import { NextRequest, NextResponse } from "next/server";
import { apiUser, jsonError, unauthorized } from "@/lib/api-auth";
import { getTeamSnapshot } from "@/lib/team";

export const dynamic = "force-dynamic";

/** GET /api/team?dept= — same staff-only presence board as web /team. */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role !== "ADMIN" && me.role !== "HR") return jsonError("Only HR / admin can view Live Team.", 403);

  const departmentId = (req.nextUrl.searchParams.get("dept") ?? "").trim();
  if (departmentId.length > 128) return jsonError("Invalid department.");
  try {
    const snapshot = await getTeamSnapshot(me.companyId, departmentId);
    return NextResponse.json(snapshot, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("[team] Could not load presence board", error);
    return jsonError("Could not load Live Team. Try again.", 500);
  }
}
