import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { canDecideFor } from "@/lib/approve-routing";
import type { SessionUser } from "@/lib/auth";

async function auth(req: NextRequest): Promise<SessionUser | null> {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

type Kind = "leave" | "gate" | "punch" | "swap";

/** POST /api/approvals/decide  {kind, id, action: "approve"|"reject"} — routed (SM/AGM/admin). */
export async function POST(req: NextRequest) {
  const me = await auth(req);
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => ({}));
  const kind = String(body.kind ?? "") as Kind;
  const id = String(body.id ?? "");
  const approve = body.action === "approve";
  if (!["leave", "gate", "punch", "swap"].includes(kind) || !id)
    return NextResponse.json({ error: "Bad request." }, { status: 400 });
  if (body.action !== "approve" && body.action !== "reject")
    return NextResponse.json({ error: 'action must be "approve" or "reject"' }, { status: 400 });

  const empInc = { department: { include: { parent: true } }, designation: true } as const;
  const decidedAt = new Date();

  if (kind === "leave") {
    const l = await db.leaveRequest.findFirst({ where: { id, companyId: me.companyId, status: "PENDING" }, include: { employee: { include: empInc } } });
    if (!l) return NextResponse.json({ error: "Not found or already decided." }, { status: 404 });
    if (!(await canDecideFor(me, l.employee as never))) return NextResponse.json({ error: "Not your approval to take." }, { status: 403 });
    await db.leaveRequest.update({ where: { id }, data: { status: approve ? "APPROVED" : "REJECTED", approverId: me.id, decidedAt } });
  } else if (kind === "gate") {
    const g = await db.gatePass.findFirst({ where: { id, companyId: me.companyId, status: "PENDING" }, include: { employee: { include: empInc } } });
    if (!g) return NextResponse.json({ error: "Not found or already decided." }, { status: 404 });
    if (!(await canDecideFor(me, g.employee as never))) return NextResponse.json({ error: "Not your approval to take." }, { status: 403 });
    await db.gatePass.update({ where: { id }, data: { status: approve ? "APPROVED" : "REJECTED", approverId: me.id, decidedAt } });
  } else if (kind === "punch") {
    const p = await db.punchRequest.findFirst({ where: { id, companyId: me.companyId, status: "PENDING" }, include: { employee: { include: empInc } } });
    if (!p) return NextResponse.json({ error: "Not found or already decided." }, { status: 404 });
    if (!(await canDecideFor(me, p.employee as never))) return NextResponse.json({ error: "Not your approval to take." }, { status: 403 });
    await db.punchRequest.update({ where: { id }, data: { status: approve ? "APPROVED" : "REJECTED", approverId: me.id, decidedAt } });
  } else {
    const s2 = await db.shiftSwapRequest.findFirst({ where: { id, companyId: me.companyId, status: "PENDING" }, include: { requester: { include: empInc } } });
    if (!s2) return NextResponse.json({ error: "Not found or already decided." }, { status: 404 });
    if (!(await canDecideFor(me, s2.requester as never))) return NextResponse.json({ error: "Not your approval to take." }, { status: 403 });
    await db.shiftSwapRequest.update({ where: { id }, data: { status: approve ? "APPROVED" : "REJECTED", decidedAt } });
  }
  return NextResponse.json({ ok: true });
}
