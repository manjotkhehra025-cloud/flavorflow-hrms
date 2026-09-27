import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { apiUser, jsonError, unauthorized } from "@/lib/api-auth";
import { getStaffRoster, saveStaffRoster } from "@/lib/roster";

export const dynamic = "force-dynamic";

function staffOrDeny(me: { role: string } | null) {
  if (!me) return unauthorized();
  if (me.role !== "ADMIN" && me.role !== "HR") {
    return jsonError("Only HR / admin can edit the duty roster.", 403);
  }
  return null;
}

/** GET /api/roster/staff?w=YYYY-MM-DD — same staff board as web /roster. */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  const deny = staffOrDeny(me);
  if (deny) return deny;

  const week = (req.nextUrl.searchParams.get("w") ?? "").trim();
  if (week.length > 32) return jsonError("Invalid week.");
  try {
    const snapshot = await getStaffRoster(me!.companyId, {
      week: week || null,
      viewerEmployeeId: me!.employeeId,
    });
    if (!snapshot.ok) return jsonError(snapshot.error, snapshot.status);
    const { ok: _ok, ...body } = snapshot;
    return NextResponse.json(body, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("[roster] Could not load duty roster", error);
    return jsonError("Could not load the duty roster. Try again.", 500);
  }
}

/** PATCH /api/roster/staff { entries: [{ employeeId, date, shiftId, isOff }] }. */
export async function PATCH(req: NextRequest) {
  const me = await apiUser(req);
  const deny = staffOrDeny(me);
  if (deny) return deny;

  const body: unknown = await req.json().catch(() => null);
  try {
    const result = await saveStaffRoster(me!.companyId, body);
    if (!result.ok) return jsonError(result.error, result.status);
    revalidatePath("/roster");
    return NextResponse.json(
      { saved: result.saved },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch (error) {
    console.error("[roster] Could not save roster", error);
    return jsonError("Could not save the roster. Try again.", 500);
  }
}
