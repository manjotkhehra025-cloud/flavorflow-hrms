import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { apiUser, jsonError, unauthorized } from "@/lib/api-auth";
import { updateTeamWeeklyOff } from "@/lib/team";

export const dynamic = "force-dynamic";

/** PATCH /api/team/weekly-off {employeeId, weeklyOff: 0..6}. */
export async function PATCH(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role !== "ADMIN" && me.role !== "HR") return jsonError("Only HR / admin can change weekly off.", 403);

  const body: unknown = await req.json().catch(() => null);
  try {
    const result = await updateTeamWeeklyOff(me.companyId, body);
    if (!result.ok) return jsonError(result.error, result.status);
    revalidatePath("/team");
    revalidatePath(`/employees/${result.employeeId}`);
    revalidatePath("/roster");
    return NextResponse.json({ employeeId: result.employeeId, weeklyOff: result.weeklyOff }, {
      headers: { "Cache-Control": "private, no-store" },
    });
  } catch (error) {
    console.error("[team] Could not save weekly off", error);
    return jsonError("Could not save weekly off. Try again.", 500);
  }
}
