import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized } from "@/lib/api-auth";
import { getAlerts } from "@/lib/alerts";

export const dynamic = "force-dynamic";

/**
 * GET /api/alerts — the same bell feed the web shows, for the app's alerts
 * sheet: routed pending approvals (SM/AGM/admin) + my recent decisions.
 * Each item carries `appPath` so a tap opens the right Flutter screen.
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const u = await db.user.findUnique({ where: { id: me.id }, select: { locale: true } });
  const lang = u?.locale === "pa" ? "pa" : "en";
  const alerts = await getAlerts(me, { lang });
  return NextResponse.json({
    count: alerts.count,
    items: alerts.items.map((a) => ({ ...a, at: a.at ? a.at.toISOString() : null })),
  });
}
