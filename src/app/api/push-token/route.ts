import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { pushEnabled } from "@/lib/push";

const schema = z.object({
  token: z.string().min(20).max(4096),
  platform: z.enum(["android", "ios"]).optional(),
});

/**
 * POST /api/push-token {token, platform} — register this phone for FCM pushes.
 * A token belongs to one login at a time: signing in as someone else on the
 * same phone moves the row, so the previous user stops getting their pushes.
 */
export async function POST(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const parsed = schema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return jsonError("Invalid token");
  const { token, platform = "android" } = parsed.data;
  await db.pushToken.upsert({
    where: { token },
    update: { userId: me.id, companyId: me.companyId, platform, lastSeenAt: new Date() },
    create: { token, userId: me.id, companyId: me.companyId, platform },
  });
  return NextResponse.json({ ok: true, serverPush: pushEnabled() });
}

/** DELETE /api/push-token {token} — logout on this phone: stop pushes to it. */
export async function DELETE(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const body = await req.json().catch(() => null);
  const token = typeof body?.token === "string" ? body.token : "";
  if (!token) return jsonError("token required");
  await db.pushToken.deleteMany({ where: { token, userId: me.id } });
  return NextResponse.json({ ok: true });
}
