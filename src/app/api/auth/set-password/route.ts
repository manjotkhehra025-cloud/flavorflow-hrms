import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import bcrypt from "bcryptjs";
import { db } from "@/lib/db";
import { getSessionUser, getUserFromToken, clearSessionCookie } from "@/lib/auth";

const schema = z.object({
  newPassword: z.string().min(6, "Password must be at least 6 characters"),
});

/**
 * POST /api/auth/set-password — first-login / after-reset flow (mobile + web).
 * Accepts the bearer token (or session cookie); validates and stores the
 * employee's OWN password, clears the force-change flag, and invalidates the
 * current session so the client MUST log in again with the new password
 * before the dashboard/home opens.
 */
export async function POST(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const parsed = schema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.issues[0]?.message ?? "Invalid payload" }, { status: 400 });
  }
  const { newPassword } = parsed.data;

  const user = await db.user.findUnique({ where: { id: me.id } });
  if (!user || !user.isActive) return NextResponse.json({ error: "Account not found" }, { status: 404 });
  if (await bcrypt.compare(newPassword, user.passwordHash)) {
    return NextResponse.json(
      { error: "New password can't be the starting one — pick something only you know." },
      { status: 409 },
    );
  }

  await db.user.update({
    where: { id: me.id },
    data: { passwordHash: await bcrypt.hash(newPassword, 10), mustChangePassword: false },
  });

  // Invalidate the active session: next boot must log in fresh.
  await clearSessionCookie();
  return NextResponse.json({ ok: true, relogin: true });
}
