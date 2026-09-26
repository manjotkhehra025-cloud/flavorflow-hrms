import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { db } from "@/lib/db";
import { permDenied } from "@/lib/permissions";
import { toDateOnly } from "@/lib/utils";
import { notifyNewRequest } from "@/lib/push";

export const dynamic = "force-dynamic";

/** GET /api/gate-passes — my passes (mobile ID-card screen; same data as web GatePassForm). */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (!me.employeeId) return NextResponse.json({ passes: [] });
  const passes = await db.gatePass.findMany({
    where: { employeeId: me.employeeId },
    orderBy: { createdAt: "desc" },
    take: 20,
  });
  return NextResponse.json({
    passes: passes.map((g) => ({
      id: g.id,
      date: g.date.toISOString(),
      exitAt: g.exitAt,
      returnAt: g.returnAt,
      reason: g.reason,
      status: g.status,
      verified: !!g.entryVerifiedAt,
    })),
  });
}

// Same rules as web createGatePassAction (src/actions/requests.ts).
const gatePassSchema = z.object({
  date: z.string().min(4, "Date required"),
  exitAt: z.string().min(4, "Exit time required"),
  returnAt: z.string().optional(),
  reason: z.string().optional(),
});

/** POST /api/gate-passes — request a pass (honours the canGatePass switch, notifies approver). */
export async function POST(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (!me.employeeId) return jsonError("Your login isn't linked to an employee profile.", 400);
  const gateDeny = await permDenied(me.employeeId, "canGatePass");
  if (gateDeny) return jsonError(gateDeny, 403);

  const body: unknown = await req.json().catch(() => null);
  const b = (body ?? {}) as Record<string, unknown>;
  const parsed = gatePassSchema.safeParse({
    date: b.date,
    exitAt: b.exitAt,
    returnAt: b.returnAt || undefined,
    reason: b.reason || undefined,
  });
  if (!parsed.success) return jsonError(parsed.error.issues[0]?.message ?? "Invalid data.", 400);
  const d = parsed.data;

  const pass = await db.gatePass.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      date: toDateOnly(d.date),
      exitAt: d.exitAt,
      returnAt: d.returnAt || null,
      reason: d.reason || null,
    },
  });
  notifyNewRequest(me.companyId, me.employeeId, "gate", `${d.date} · ${d.exitAt}`);
  return NextResponse.json({ ok: true, id: pass.id });
}
