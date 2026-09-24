import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { toDateOnly } from "@/lib/utils";

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

/** GET /api/requests — my manual punch / OT requests (mobile "My requests" strip). */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ requests: [] });
  const requests = await db.punchRequest.findMany({
    where: { employeeId: me.employeeId },
    orderBy: { createdAt: "desc" },
    take: 20,
  });
  return NextResponse.json({ requests });
}

/** POST /api/requests — manual punch in/out or OT (routes to the designation-based approver). */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  const { getPerms } = await import("@/lib/permissions");
  const perms = await getPerms(me.employeeId);
  if (!perms.canPunch) {
    return NextResponse.json({ error: "Manual punch requests are turned OFF for you — ask the super admin." }, { status: 403 });
  }

  const body = await req.json().catch(() => ({}));
  const type = String(body?.type ?? "");
  const date = body?.date ? toDateOnly(String(body.date)) : null;
  const time = body?.time ? String(body.time) : null;
  const hours = body?.hours != null ? Number(body.hours) : null;
  const reason = String(body?.reason ?? "").trim();

  if (!["MANUAL_IN", "MANUAL_OUT", "OT"].includes(type)) {
    return NextResponse.json({ error: "type must be MANUAL_IN | MANUAL_OUT | OT" }, { status: 400 });
  }
  if (!date) return NextResponse.json({ error: "date is required (YYYY-MM-DD)" }, { status: 400 });
  if (type !== "OT" && !time) return NextResponse.json({ error: "time is required for manual punch" }, { status: 400 });
  if (type === "OT" && (!Number.isFinite(hours) || hours! <= 0 || hours! > 12)) {
    return NextResponse.json({ error: "OT hours must be 0.5-12" }, { status: 400 });
  }
  if (reason.length < 3) return NextResponse.json({ error: "reason is required (at least a few words)" }, { status: 400 });

  const dup = await db.punchRequest.findFirst({
    where: { employeeId: me.employeeId, date, type, status: "PENDING" },
  });
  if (dup) return NextResponse.json({ error: "You already have a pending request of this type for this date." }, { status: 409 });

  const request = await db.punchRequest.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      type: type as never,
      date,
      time: type === "OT" ? null : time,
      hours: type === "OT" ? hours : null,
      reason,
    },
  });
  return NextResponse.json({ request }, { status: 201 });
}
