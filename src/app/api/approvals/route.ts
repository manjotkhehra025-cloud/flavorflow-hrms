import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { approverScope, filterByScope } from "@/lib/approve-routing";
import type { SessionUser } from "@/lib/auth";

async function auth(req: NextRequest): Promise<SessionUser | null> {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

const empInc = { department: { include: { parent: true } }, designation: true } as const;

/** GET /api/approvals — routed inbox for the caller (SM sees group A, AGM group B, admin all). */
export async function GET(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const scope = await approverScope(me);
  if (!scope) return NextResponse.json({ error: "Not an approver." }, { status: 403 });

  const [leaves, punches, gates, swaps] = await Promise.all([
    db.leaveRequest.findMany({
      where: { companyId: me.companyId, status: "PENDING" },
      include: { employee: { include: empInc }, leaveType: true },
      orderBy: { createdAt: "asc" },
    }),
    db.punchRequest.findMany({
      where: { companyId: me.companyId, status: "PENDING" },
      include: { employee: { include: empInc } },
      orderBy: { createdAt: "asc" },
    }),
    db.gatePass.findMany({
      where: { companyId: me.companyId, status: "PENDING" },
      include: { employee: { include: empInc } },
      orderBy: { createdAt: "asc" },
    }),
    db.shiftSwapRequest.findMany({
      where: { companyId: me.companyId, status: "PENDING" },
      include: { requester: { include: empInc }, peer: true },
      orderBy: { createdAt: "asc" },
    }),
  ]);

  const inScope = <T extends { category?: string; department?: unknown }>(e: T) =>
    scope === "ALL" || filterByScope([e as never], scope).length === 1;

  const strip = <T extends { firstName: string; lastName: string; code: string }>(e: T) =>
    ({ name: `${e.firstName} ${e.lastName}`, code: e.code });

  return NextResponse.json({
    scope,
    leaves: leaves.filter((l) => inScope(l.employee)).map((l) => ({
      id: l.id, kind: "leave", employee: strip(l.employee), type: l.leaveType.name,
      from: l.fromDate, to: l.toDate, days: l.days, reason: l.reason, at: l.createdAt,
    })),
    punches: punches.filter((p) => inScope(p.employee)).map((p) => ({
      id: p.id, kind: "punch", employee: strip(p.employee), type: p.type,
      date: p.date, time: p.time, hours: p.hours, reason: p.reason, at: p.createdAt,
    })),
    gates: gates.filter((g) => inScope(g.employee)).map((g) => ({
      id: g.id, kind: "gate", employee: strip(g.employee),
      date: g.date, exitAt: g.exitAt, returnAt: g.returnAt, reason: g.reason, at: g.createdAt,
    })),
    swaps: swaps.filter((s2) => inScope(s2.requester)).map((s2) => ({
      id: s2.id, kind: "swap", employee: strip(s2.requester),
      peer: strip(s2.peer), date: s2.date, note: s2.note, at: s2.createdAt,
    })),
  });
}
