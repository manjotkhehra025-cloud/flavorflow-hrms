import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { buildMonthlyAttendance, monthRange, currentMonth, toCsv } from "@/lib/reports";

/** GET /api/reports/attendance?month=2026-09 — CSV download (staff only). */
export async function GET(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (me.role === "EMPLOYEE") return NextResponse.json({ error: "Staff only" }, { status: 403 });

  const month = req.nextUrl.searchParams.get("month") || currentMonth();
  const rows = await buildMonthlyAttendance(me.companyId, month);
  const csv = toCsv(rows, monthRange(month).label);

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="attendance-${month}.csv"`,
    },
  });
}
