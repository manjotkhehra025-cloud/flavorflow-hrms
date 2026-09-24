import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { toDateOnly, dayDiffInclusive } from "@/lib/utils";

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

/** GET /api/leaves — my leave requests + types + LIVE balances (mobile P3). */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ requests: [], leaveTypes: [], balances: [] });

  const [requests, leaveTypes, employee] = await Promise.all([
    db.leaveRequest.findMany({
      where: { employeeId: me.employeeId },
      include: { leaveType: true },
      orderBy: { createdAt: "desc" },
      take: 50,
    }),
    db.leaveType.findMany({ where: { companyId: me.companyId } }),
    db.employee.findUnique({ where: { id: me.employeeId }, select: { id: true, category: true, joinDate: true } }),
  ]);
  let balances: unknown[] = [];
  if (employee) {
    const { getLeaveBalances, balanceRemaining } = await import("@/lib/balances");
    balances = (await getLeaveBalances(employee, me.companyId)).map((b) => ({
      leaveTypeId: b.leaveTypeId,
      name: b.name,
      quota: b.quota,
      used: b.used,
      pending: b.pending,
      remaining: balanceRemaining(b), // null = unlimited (LOP-type)
    }));
  }
  return NextResponse.json({ requests, leaveTypes, balances });
}

const applySchema = z.object({
  leaveTypeId: z.string(),
  fromDate: z.string(),
  toDate: z.string(),
  reason: z.string().optional(),
  halfDay: z.boolean().optional(),
});

/** POST /api/leaves — apply for leave (canApplyLeave-enforced, overlap-guarded). */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  // Super-admin feature switch: applying leave can be disabled per employee.
  const { getPerms } = await import("@/lib/permissions");
  const perms = await getPerms(me.employeeId);
  if (!perms.canApplyLeave) {
    return NextResponse.json({ error: "Leave apply is turned OFF for you — ask the super admin." }, { status: 403 });
  }

  const parsed = applySchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Invalid payload" }, { status: 400 });

  const from = toDateOnly(parsed.data.fromDate);
  const to = toDateOnly(parsed.data.toDate);
  if (to < from) return NextResponse.json({ error: "End date before start date" }, { status: 400 });

  // Overlap guard: an active (pending/approved) request already covering these days.
  const clash = await db.leaveRequest.findFirst({
    where: {
      employeeId: me.employeeId,
      status: { in: ["PENDING", "APPROVED"] },
      fromDate: { lte: to },
      toDate: { gte: from },
    },
    select: { fromDate: true, toDate: true },
  });
  if (clash) return NextResponse.json({ error: "You already have a leave covering these days." }, { status: 409 });

  const request = await db.leaveRequest.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      leaveTypeId: parsed.data.leaveTypeId,
      fromDate: from,
      toDate: to,
      days: dayDiffInclusive(from, to),
      halfDay: parsed.data.halfDay === true,
      reason: parsed.data.reason,
    },
    include: { leaveType: true },
  });
  return NextResponse.json({ request }, { status: 201 });
}
