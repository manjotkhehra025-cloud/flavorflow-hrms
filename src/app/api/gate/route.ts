import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { makeGateQr, verifyGateQr } from "@/lib/gate-qr";

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

/** GET /api/gate — my QR token (client re-requests when refreshInSec elapses). */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  const emp = await db.employee.findFirst({
    where: { id: me.employeeId, companyId: me.companyId, status: "ACTIVE" },
    select: { code: true },
  });
  if (!emp) return NextResponse.json({ error: "Employee not found or inactive" }, { status: 404 });
  return NextResponse.json(makeGateQr(emp.code));
}

const verifySchema = z.object({ token: z.string().min(12).max(200) });

/**
 * POST /api/gate {token} — gatekeeper scan-verify: returns the scanned employee's
 * identity + today's punch status (mockup p4-gatekeeper).
 */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const parsed = verifySchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Invalid token" }, { status: 400 });

  const v = verifyGateQr(parsed.data.token);
  if (!v) {
    return NextResponse.json({ verified: false, error: "QR is expired or fake — ask them to reopen it." }, { status: 422 });
  }

  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);
  const emp = await db.employee.findFirst({
    where: { code: v.code, companyId: me.companyId },
    include: {
      department: true,
      designation: true,
      shift: true,
      attendances: { where: { date: today }, take: 1 },
    },
  });
  if (!emp) return NextResponse.json({ verified: false, error: "Employee not in this company" }, { status: 404 });

  const rec = emp.attendances[0] ?? null;
  return NextResponse.json({
    verified: true,
    employee: {
      id: emp.id,
      name: `${emp.firstName} ${emp.lastName}`,
      code: emp.code,
      department: emp.department?.name ?? null,
      designation: emp.designation?.title ?? null,
      status: emp.status,
      shift: emp.shift ? { name: emp.shift.name, startTime: emp.shift.startTime, durationH: emp.shift.durationH } : null,
      photoUrl: `/api/photo/${emp.id}`,
    },
    today: rec
      ? {
          status: rec.status,
          checkedIn: rec.checkIn ? rec.checkIn.toISOString() : null,
          checkedOut: rec.checkOut ? rec.checkOut.toISOString() : null,
        }
      : { status: "NOT_PUNCHED", checkedIn: null, checkedOut: null },
  });
}
