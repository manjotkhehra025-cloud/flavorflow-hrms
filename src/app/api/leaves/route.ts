import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { toDateOnly, dayDiffInclusive } from "@/lib/utils";

async function auth(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

/** GET /api/leaves — my leave requests. */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ requests: [], leaveTypes: [] });

  const [requests, leaveTypes] = await Promise.all([
    db.leaveRequest.findMany({
      where: { employeeId: me.employeeId },
      include: { leaveType: true },
      orderBy: { createdAt: "desc" },
      take: 50,
    }),
    db.leaveType.findMany({ where: { companyId: me.companyId } }),
  ]);
  return NextResponse.json({ requests, leaveTypes });
}

const applySchema = z.object({
  leaveTypeId: z.string(),
  fromDate: z.string(),
  toDate: z.string(),
  reason: z.string().optional(),
});

/** POST /api/leaves — apply for leave. */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (!me.employeeId) return NextResponse.json({ error: "No employee profile linked" }, { status: 400 });

  const parsed = applySchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Invalid payload" }, { status: 400 });

  const from = toDateOnly(parsed.data.fromDate);
  const to = toDateOnly(parsed.data.toDate);
  if (to < from) return NextResponse.json({ error: "End date before start date" }, { status: 400 });

  const request = await db.leaveRequest.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      leaveTypeId: parsed.data.leaveTypeId,
      fromDate: from,
      toDate: to,
      days: dayDiffInclusive(from, to),
      reason: parsed.data.reason,
    },
    include: { leaveType: true },
  });
  return NextResponse.json({ request }, { status: 201 });
}
