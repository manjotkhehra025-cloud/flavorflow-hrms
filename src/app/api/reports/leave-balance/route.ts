import { NextRequest, NextResponse } from "next/server";
import ExcelJS from "exceljs";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { buildLeaveBalanceRegister } from "@/lib/reports2";

/** GET /api/reports/leave-balance — leave balance register as .xlsx (staff only, year-to-date snapshot). */
export async function GET(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (me.role === "EMPLOYEE") return NextResponse.json({ error: "Staff only" }, { status: 403 });

  const { types, rows } = await buildLeaveBalanceRegister(me.companyId);
  const year = new Date().getUTCFullYear();
  const asOf = new Date().toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Kolkata" });

  const wb = new ExcelJS.Workbook();
  wb.creator = "HRMate";
  const ws = wb.addWorksheet("Leave balance", { views: [{ state: "frozen", xSplit: 2, ySplit: 3 }] });

  const nCols = 3 + types.length * 3;
  ws.getColumn(1).width = 24;
  ws.getColumn(2).width = 9;
  ws.getColumn(3).width = 16;

  const t1 = ws.addRow([`Leave Balance Register — ${year}  ·  ${me.companyName}`]);
  ws.mergeCells(1, 1, 1, nCols);
  t1.height = 26;
  t1.font = { size: 14, bold: true, color: { argb: "FFFFFFFF" } };
  t1.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF0A1628" } };
  t1.alignment = { vertical: "middle", indent: 1 };

  const t2 = ws.addRow([`As of ${asOf} · per leave type: Quota / Used / Balance · EL for yellow-card staff accrues 1.25/month`]);
  ws.mergeCells(2, 1, 2, nCols);
  t2.font = { size: 9, italic: true, color: { argb: "FF475569" } };

  // header: Employee | Code | Dept | [Type: Quota Used Balance]...
  const head = ws.addRow(["Employee", "Code", "Department", ...types.flatMap((t) => [`${t.name} (Q)`, "Used", "Bal"])]);
  head.height = 18;
  head.font = { size: 9, bold: true, color: { argb: "FFFFFFFF" } };
  head.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF059669" } };
  head.alignment = { vertical: "middle", horizontal: "center" };
  for (let i = 0; i < types.length * 3; i++) ws.getColumn(4 + i).width = 7;

  rows.forEach((r, i) => {
    const byType = new Map(r.balances.map((b) => [b.leaveTypeId, b]));
    const row = ws.addRow([
      r.name, r.code, r.department ?? "",
      ...types.flatMap((t) => {
        const b = byType.get(t.id);
        if (!b) return ["", "", ""];
        const bal = t.daysPerYear === 0 ? "∞" : b.balance;
        return [t.daysPerYear === 0 ? "∞" : b.quota, b.used, bal];
      }),
    ]);
    row.font = { size: 9 };
    row.getCell(1).font = { size: 9, bold: true };
    if (i % 2 === 1) row.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF1F5F9" } };
  });

  const buf = Buffer.from(await wb.xlsx.writeBuffer());
  return new NextResponse(new Uint8Array(buf), {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="leave-balance-${year}.xlsx"`,
    },
  });
}
