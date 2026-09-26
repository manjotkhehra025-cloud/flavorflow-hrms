import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { todayDate } from "@/lib/utils";

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

/** GET /api/attendance — my attendance, newest first (?take=30) + today/shift block for home. */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ records: [], today: null });

  const take = Math.min(Number(req.nextUrl.searchParams.get("take")) || 30, 90);
  const date = todayDate();
  const [records, today, emp, pendingPunch, pendingOT] = await Promise.all([
    db.attendance.findMany({
      where: { employeeId: me.employeeId },
      orderBy: { date: "desc" },
      take,
    }),
    db.attendance.findUnique({
      where: { employeeId_date: { employeeId: me.employeeId, date } },
    }),
    db.employee.findUnique({
      where: { id: me.employeeId },
      include: { shift: true },
    }),
    db.punchRequest.count({
      where: { employeeId: me.employeeId, status: "PENDING", type: { not: "OT" } },
    }),
    db.punchRequest.count({
      where: { employeeId: me.employeeId, status: "PENDING", type: "OT" },
    }),
  ]);

  const chipPending: { key: string; label: string }[] = [];
  const company = emp?.companyId
    ? await db.company.findUnique({
        where: { id: emp.companyId },
        select: { geofenceEnabled: true, name: true },
      })
    : null;

  return NextResponse.json({
    records,
    today,
    shift: emp?.shift
      ? { name: emp.shift.name, startTime: emp.shift.startTime, durationH: emp.shift.durationH }
      : { name: "General Day Shift", startTime: "08:00", durationH: 9 },
    isWeeklyOff: emp ? date.getUTCDay() === emp.weeklyOff : false,
    geofenceEnabled: company?.geofenceEnabled ?? false,
    companyName: emp ? company?.name ?? null : null,
    chips: {
      pendingOT,
      pendingPunch,
    },
  });
}

/** POST /api/attendance  { "action": "checkin" | "checkout", lat?, lng?, acc?, selfieRef? } */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  // Super-admin feature switch: self punch can be disabled per employee.
  const { getPerms } = await import("@/lib/permissions");
  const perms = await getPerms(me.employeeId);
  if (!perms.canPunch) {
    return NextResponse.json({ error: "Self punch is turned OFF for you — ask the super admin." }, { status: 403 });
  }

  const body = await req.json().catch(() => ({}));
  const action = body?.action;
  const lat = typeof body?.lat === "number" ? body.lat : undefined;
  const lng = typeof body?.lng === "number" ? body.lng : undefined;
  const acc = typeof body?.acc === "number" ? body.acc : undefined;
  const selfieRef = typeof body?.selfieRef === "string" ? body.selfieRef : undefined;
  const date = todayDate();

  // Factory geofence enforcement (same rule the web applies).
  const c = await db.company.findUnique({
    where: { id: me.companyId },
    select: { geofenceEnabled: true, geoLat: true, geoLng: true, geoRadius: true, name: true },
  });
  let punchDist: number | null = null;
  if (c?.geofenceEnabled && c.geoLat != null && c.geoLng != null) {
    if (lat == null || lng == null) {
      return NextResponse.json({ error: "Location is required to punch inside the factory." }, { status: 400 });
    }
    // Same 150 m cap as the clients: a coarser fix cannot prove fence membership.
    if (acc != null && acc > 150) {
      return NextResponse.json(
        { error: `GPS too weak (\u00b1${Math.round(acc)}m) \u2014 stand in the open and retry.` },
        { status: 400 },
      );
    }
    const { distanceMeters } = await import("@/lib/utils");
    const dist = distanceMeters(lat, lng, c.geoLat, c.geoLng);
    if (dist > c.geoRadius) {
      return NextResponse.json(
        { error: `You're ${Math.round(dist)} m away — move inside the factory geofence (${c.geoRadius} m) to punch.` },
        { status: 422 },
      );
    }
    punchDist = Math.round(dist);
  }
  const geo = lat != null && lng != null ? { punchLat: lat, punchLng: lng, punchDist } : {};

  const existing = await db.attendance.findUnique({
    where: { employeeId_date: { employeeId: me.employeeId, date } },
  });

  if (action === "checkin") {
    if (existing?.checkIn) return NextResponse.json({ error: "Already checked in" }, { status: 409 });
    const record = await db.attendance.upsert({
      where: { employeeId_date: { employeeId: me.employeeId, date } },
      create: {
        companyId: me.companyId, employeeId: me.employeeId, date, checkIn: new Date(), status: "PRESENT",
        selfiePath: selfieRef ?? null, ...geo,
      },
      update: { checkIn: new Date(), status: "PRESENT", selfiePath: selfieRef ?? null, ...geo },
    });
    return NextResponse.json({ record });
  }

  if (action === "checkout") {
    if (!existing?.checkIn) return NextResponse.json({ error: "Check in first" }, { status: 409 });
    if (existing.checkOut) return NextResponse.json({ error: "Already checked out" }, { status: 409 });
    const record = await db.attendance.update({ where: { id: existing.id }, data: { checkOut: new Date(), ...geo } });
    return NextResponse.json({ record });
  }

  return NextResponse.json({ error: "action must be 'checkin' or 'checkout'" }, { status: 400 });
}
