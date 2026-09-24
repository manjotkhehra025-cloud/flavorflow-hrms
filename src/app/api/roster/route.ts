import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { toDateOnly } from "@/lib/utils";

const DAY = 24 * 60 * 60 * 1000;

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

function mondayOf(d: Date): Date {
  const dow = d.getUTCDay();
  const base = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  return new Date(base.getTime() - ((dow + 6) % 7) * DAY);
}

/** GET /api/roster(?w=YYYY-MM-DD anchor) — my week: 7 days of shift + swaps. */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ days: [], swaps: [], peers: [] });

  const anchor = req.nextUrl.searchParams.get("w");
  const mon = anchor ? toDateOnly(anchor) : mondayOf(new Date());
  const sun = new Date(mon.getTime() + 6 * DAY);

  const emp = await db.employee.findFirst({
    where: { id: me.employeeId },
    include: { shift: true },
  });
  if (!emp) return NextResponse.json({ days: [], swaps: [], peers: [] });

  const [assignments, swapsRaw, peers] = await Promise.all([
    db.shiftAssignment.findMany({
      where: { employeeId: emp.id, date: { gte: mon, lte: sun } },
      include: { shift: true },
    }),
    db.shiftSwapRequest.findMany({
      where: {
        companyId: me.companyId,
        OR: [{ requesterId: emp.id }, { peerId: emp.id }],
        date: { gte: mon, lte: sun },
      },
      include: { requester: { select: { firstName: true, lastName: true, code: true } }, peer: { select: { firstName: true, lastName: true, code: true } } },
    }),
    // coworkers I can propose a swap with (same company, active, not me)
    db.employee.findMany({
      where: { companyId: me.companyId, status: "ACTIVE", id: { not: emp.id } },
      select: { id: true, firstName: true, lastName: true, code: true, department: { select: { name: true } } },
      orderBy: { firstName: "asc" },
      take: 200,
    }),
  ]);

  const byDate = new Map(assignments.map((a) => [a.date.toISOString().slice(0, 10), a]));
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(mon.getTime() + i * DAY);
    const key = d.toISOString().slice(0, 10);
    const a = byDate.get(key);
    const isSunday = d.getUTCDay() === 0;
    const off = a ? a.isOff : isSunday; // no override row ⇒ Sunday default off
    const shift = a?.shift ?? emp.shift ?? null;
    return {
      date: key,
      weekday: d.getUTCDay(),
      isToday: key === new Date().toISOString().slice(0, 10),
      off,
      shift: off ? null : shift ? { name: shift.name, startTime: shift.startTime, durationH: shift.durationH } : null,
    };
  });

  const swaps = swapsRaw.map((s2) => ({
    id: s2.id,
    date: s2.date.toISOString().slice(0, 10),
    status: s2.status,
    otherPerson: s2.requesterId === emp.id ? s2.peer : s2.requester,
    mine: s2.requesterId === emp.id,
    note: s2.note,
  }));

  return NextResponse.json({
    weekStart: mon.toISOString().slice(0, 10),
    days,
    swaps,
    peers: peers.map((p) => ({
      id: p.id,
      name: `${p.firstName} ${p.lastName}`,
      code: p.code,
      department: p.department?.name ?? null,
    })),
  });
}

const swapSchema = z.object({
  peerId: z.string(),
  date: z.string(),
  note: z.string().max(200).optional(),
});

/** POST /api/roster — request a shift swap with a coworker (canSwapShift-gated). */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  const { getPerms } = await import("@/lib/permissions");
  const perms = await getPerms(me.employeeId);
  if (!perms.canSwapShift) {
    return NextResponse.json({ error: "Shift swap is turned OFF for you — ask the super admin." }, { status: 403 });
  }

  const parsed = swapSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Invalid payload" }, { status: 400 });

  const date = toDateOnly(parsed.data.date);
  if (parsed.data.peerId === me.employeeId) {
    return NextResponse.json({ error: "You cannot swap with yourself." }, { status: 400 });
  }

  const peer = await db.employee.findFirst({
    where: { id: parsed.data.peerId, companyId: me.companyId, status: "ACTIVE" },
  });
  if (!peer) return NextResponse.json({ error: "Coworker not found" }, { status: 404 });

  const dup = await db.shiftSwapRequest.findFirst({
    where: { companyId: me.companyId, requesterId: me.employeeId, date, status: "PENDING" },
  });
  if (dup) return NextResponse.json({ error: "A pending swap for this date already exists." }, { status: 409 });

  const swap = await db.shiftSwapRequest.create({
    data: {
      companyId: me.companyId,
      requesterId: me.employeeId,
      peerId: peer.id,
      date,
      note: parsed.data.note?.trim() || null,
    },
  });
  return NextResponse.json({ swap }, { status: 201 });
}
