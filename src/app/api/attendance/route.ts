import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { todayDate } from "@/lib/utils";

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

/** GET /api/attendance — my attendance, newest first (?take=30). */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ records: [] });

  const take = Math.min(Number(req.nextUrl.searchParams.get("take")) || 30, 90);
  const records = await db.attendance.findMany({
    where: { employeeId: me.employeeId },
    orderBy: { date: "desc" },
    take,
  });
  return NextResponse.json({ records });
}

/** POST /api/attendance  { "action": "checkin" | "checkout" } */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  const body = await req.json().catch(() => ({}));
  const action = body?.action;
  const date = todayDate();

  const existing = await db.attendance.findUnique({
    where: { employeeId_date: { employeeId: me.employeeId, date } },
  });

  if (action === "checkin") {
    if (existing?.checkIn) return NextResponse.json({ error: "Already checked in" }, { status: 409 });
    const record = await db.attendance.upsert({
      where: { employeeId_date: { employeeId: me.employeeId, date } },
      create: { companyId: me.companyId, employeeId: me.employeeId, date, checkIn: new Date(), status: "PRESENT" },
      update: { checkIn: new Date(), status: "PRESENT" },
    });
    return NextResponse.json({ record });
  }

  if (action === "checkout") {
    if (!existing?.checkIn) return NextResponse.json({ error: "Check in first" }, { status: 409 });
    if (existing.checkOut) return NextResponse.json({ error: "Already checked out" }, { status: 409 });
    const record = await db.attendance.update({ where: { id: existing.id }, data: { checkOut: new Date() } });
    return NextResponse.json({ record });
  }

  return NextResponse.json({ error: "action must be 'checkin' or 'checkout'" }, { status: 400 });
}
