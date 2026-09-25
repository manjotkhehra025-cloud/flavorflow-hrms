import { NextRequest, NextResponse } from "next/server";
import { apiUser, unauthorized } from "@/lib/api-auth";
import { decideApproval } from "@/lib/decide";

/** POST /api/approvals/decide  {kind, id, action: "approve"|"reject"} — routed (SM/AGM/admin). */
export async function POST(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const body = await req.json().catch(() => ({}));
  const kind = String(body.kind ?? "");
  const id = String(body.id ?? "");
  if (body.action !== "approve" && body.action !== "reject") {
    return NextResponse.json({ error: 'action must be "approve" or "reject"' }, { status: 400 });
  }
  const result = await decideApproval(me, { kind, id, approve: body.action === "approve" });
  if (!result.ok) return NextResponse.json({ error: result.error }, { status: result.status });
  return NextResponse.json({ ok: true });
}
