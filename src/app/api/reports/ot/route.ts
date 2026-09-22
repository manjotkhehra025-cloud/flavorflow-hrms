import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { buildOt, hoursFmt } from "@/lib/reports2";
import { currentMonth } from "@/lib/reports";
import { makeXlsx } from "@/lib/xlsx";

/** GET /api/reports/ot?month=2026-09 — overtime report as .xlsx (staff only). */
export async function GET(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (me.role === "EMPLOYEE") return NextResponse.json({ error: "Staff only" }, { status: 403 });

  const month = req.nextUrl.searchParams.get("month") || currentMonth();
  const { label, rows, totalOt } = await buildOt(me.companyId, month);

  const buf = await makeXlsx({
    title: `Overtime Report — ${label}`,
    subtitle: `Total OT: ${hoursFmt(totalOt)} hrs · punch OT = worked hours beyond shift length · manual OT = approved OT requests · ${me.companyName}`,
    sheetName: "OT",
    columns: [
      { header: "Date", width: 12 },
      { header: "Employee", width: 24 },
      { header: "Code", width: 9 },
      { header: "Department", width: 16 },
      { header: "Worked (hrs)", width: 12 },
      { header: "Shift (hrs)", width: 11 },
      { header: "OT (hrs)", width: 9 },
      { header: "Source", width: 13 },
    ],
    rows: [
      ...rows.map((r) => [
        r.dayLabel,
        r.name,
        r.code,
        r.department ?? "",
        r.workedHours === null ? "—" : hoursFmt(r.workedHours),
        r.shiftHours === null ? "—" : hoursFmt(r.shiftHours),
        hoursFmt(r.otHours),
        r.source === "PUNCH" ? "Punch" : "Approved OT request",
      ]),
      ["", "TOTAL", "", "", "", "", hoursFmt(totalOt), ""],
    ],
    zebra: true,
  });

  return new NextResponse(new Uint8Array(buf), {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="ot-report-${month}.xlsx"`,
    },
  });
}
