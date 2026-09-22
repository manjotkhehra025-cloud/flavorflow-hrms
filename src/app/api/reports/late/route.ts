import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { buildLateIn, LATE_GRACE_MINS } from "@/lib/reports2";
import { currentMonth } from "@/lib/reports";
import { makeXlsx } from "@/lib/xlsx";

/** GET /api/reports/late?month=2026-09 — late-in report as .xlsx (staff only). */
export async function GET(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (me.role === "EMPLOYEE") return NextResponse.json({ error: "Staff only" }, { status: 403 });

  const month = req.nextUrl.searchParams.get("month") || currentMonth();
  const { label, rows } = await buildLateIn(me.companyId, month);

  const buf = await makeXlsx({
    title: `Late-in Report — ${label}`,
    subtitle: `${rows.length} late check-ins · grace allowed: ${LATE_GRACE_MINS} minutes after shift start · ${me.companyName}`,
    sheetName: "Late-in",
    columns: [
      { header: "Date", width: 12 },
      { header: "Employee", width: 24 },
      { header: "Code", width: 9 },
      { header: "Department", width: 16 },
      { header: "Shift start", width: 11 },
      { header: "Check-in", width: 10 },
      { header: "Late by", width: 10 },
    ],
    rows: rows.map((r) => [
      r.dayLabel,
      r.name,
      r.code,
      r.department ?? "",
      r.shiftStart,
      r.checkIn,
      `${r.lateByMins} min`,
    ]),
  });

  return new NextResponse(new Uint8Array(buf), {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="late-in-${month}.xlsx"`,
    },
  });
}
