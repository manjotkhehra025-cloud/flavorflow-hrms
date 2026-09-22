import { NextRequest, NextResponse } from "next/server";
import ExcelJS from "exceljs";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { buildRegisterGrid } from "@/lib/reports2";
import { currentMonth } from "@/lib/reports";
import { CELL_FILLS, CELL_FONTS } from "@/lib/xlsx";

/** GET /api/reports/register?month=2026-09 — monthly register grid as .xlsx (staff only). */
export async function GET(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (me.role === "EMPLOYEE") return NextResponse.json({ error: "Staff only" }, { status: 403 });

  const month = req.nextUrl.searchParams.get("month") || currentMonth();
  const grid = await buildRegisterGrid(me.companyId, month);

  const wb = new ExcelJS.Workbook();
  wb.creator = "HRMate";
  const ws = wb.addWorksheet("Register", { views: [{ state: "frozen", xSplit: 2, ySplit: 3 }] });

  const nCols = 2 + grid.daysInMonth + 4;
  ws.getColumn(1).width = 22;
  ws.getColumn(2).width = 9;

  // Title
  const t1 = ws.addRow([`Attendance Register — ${grid.label}  ·  ${me.companyName}`]);
  ws.mergeCells(1, 1, 1, nCols);
  t1.height = 26;
  t1.font = { size: 14, bold: true, color: { argb: "FFFFFFFF" } };
  t1.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF0A1628" } };
  t1.alignment = { vertical: "middle", indent: 1 };

  // Legend
  const t2 = ws.addRow(["P Present   A Absent   L Leave   W Weekly off   H Holiday"]);
  ws.mergeCells(2, 1, 2, nCols);
  t2.font = { size: 9, italic: true, color: { argb: "FF475569" } };
  t2.height = 16;

  // Header: Employee | Code | 1..N | P | A | L | W
  const head = ["Employee", "Code"];
  for (let d = 1; d <= grid.daysInMonth; d++) {
    head.push(String(d));
    ws.getColumn(2 + d).width = 3.6;
  }
  head.push("P", "A", "L", "W");
  for (let i = 0; i < 4; i++) ws.getColumn(2 + grid.daysInMonth + 1 + i).width = 5;
  const hr = ws.addRow(head);
  hr.height = 18;
  hr.font = { size: 9, bold: true, color: { argb: "FFFFFFFF" } };
  hr.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF059669" } };
  hr.alignment = { vertical: "middle", horizontal: "center" };

  // Sunday shading on header day cells
  for (let d = 1; d <= grid.daysInMonth; d++) {
    if (grid.sundays[d - 1]) {
      hr.getCell(2 + d).fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF0F766E" } };
    }
  }

  // Data rows
  grid.rows.forEach((r) => {
    const row = ws.addRow([
      r.name,
      r.code,
      ...r.cells.map((c) => c.code),
      r.present, r.absent, r.leave, r.weeklyOff,
    ]);
    row.font = { size: 9 };
    row.getCell(1).font = { size: 9, bold: true };
    r.cells.forEach((c, i) => {
      if (!c.code) return;
      const cell = row.getCell(3 + i);
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: CELL_FILLS[c.code] } };
      cell.font = { size: 9, bold: true, color: { argb: CELL_FONTS[c.code] } };
      cell.alignment = { horizontal: "center" };
      if (c.inAt) cell.note = `In at ${c.inAt}`;
      if (c.note) cell.note = c.note;
    });
    // totals
    [r.present, r.absent, r.leave, r.weeklyOff].forEach((_, i) => {
      row.getCell(2 + grid.daysInMonth + 1 + i).alignment = { horizontal: "center" };
    });
    row.getCell(2 + grid.daysInMonth + 1).font = { size: 9, bold: true, color: { argb: "FF047857" } };
    if (r.absent > 0) row.getCell(2 + grid.daysInMonth + 2).font = { size: 9, bold: true, color: { argb: "FFB91C1C" } };
  });

  const buf = Buffer.from(await wb.xlsx.writeBuffer());
  return new NextResponse(new Uint8Array(buf), {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="attendance-register-${month}.xlsx"`,
    },
  });
}
