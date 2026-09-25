import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { todayDate, toDateOnly } from "@/lib/utils";

export const dynamic = "force-dynamic";

const DAY = 24 * 60 * 60 * 1000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

/**
 * GET /api/holidays(?year=2026) — company holiday calendar for the year plus the
 * next upcoming holiday (may be in the following year) with a days-left count.
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();

  const today = todayDate();
  const qYear = Number(req.nextUrl.searchParams.get("year"));
  const year = Number.isInteger(qYear) && qYear >= 2000 && qYear <= 2100 ? qYear : today.getUTCFullYear();

  const [holidays, next] = await Promise.all([
    db.holiday.findMany({
      where: {
        companyId: me.companyId,
        date: { gte: new Date(Date.UTC(year, 0, 1)), lte: new Date(Date.UTC(year, 11, 31)) },
      },
      orderBy: { date: "asc" },
    }),
    db.holiday.findFirst({
      where: { companyId: me.companyId, date: { gte: today } },
      orderBy: { date: "asc" },
    }),
  ]);

  return NextResponse.json({
    year,
    today: iso(today),
    canEdit: me.role !== "EMPLOYEE",
    holidays: holidays.map((h) => ({
      id: h.id,
      name: h.name,
      date: iso(h.date),
      past: h.date < today,
    })),
    next: next ? { id: next.id, name: next.name, date: iso(next.date), daysLeft: Math.round((next.date.getTime() - today.getTime()) / DAY) } : null,
  });
}

/** POST /api/holidays {name, date:"YYYY-MM-DD"} — ADMIN/HR. Same side-effect as web: ABSENT-without-punch → HOLIDAY. */
export async function POST(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role === "EMPLOYEE") return jsonError("Only HR / admin can edit holidays.", 403);
  const body = await req.json().catch(() => null);
  const name = String(body?.name ?? "").trim();
  const date = String(body?.date ?? "");
  if (!name || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return jsonError("Name and date (YYYY-MM-DD) are required.");
  const day = toDateOnly(date);
  const holiday = await db.holiday.upsert({
    where: { companyId_date: { companyId: me.companyId, date: day } },
    create: { companyId: me.companyId, name, date: day },
    update: { name },
  });
  await db.attendance.updateMany({
    where: { companyId: me.companyId, date: day, checkIn: null, status: "ABSENT" },
    data: { status: "HOLIDAY", note: name },
  });
  return NextResponse.json({ holiday: { id: holiday.id, name: holiday.name, date: iso(holiday.date) } }, { status: 201 });
}

/** DELETE /api/holidays?id=… — ADMIN/HR. */
export async function DELETE(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role === "EMPLOYEE") return jsonError("Only HR / admin can edit holidays.", 403);
  const id = req.nextUrl.searchParams.get("id") ?? "";
  const { count } = await db.holiday.deleteMany({ where: { id, companyId: me.companyId } });
  if (!count) return jsonError("Holiday not found.", 404);
  return NextResponse.json({ ok: true });
}
