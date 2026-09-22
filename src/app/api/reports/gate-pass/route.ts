import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { buildGatePassLog } from "@/lib/reports2";
import { currentMonth } from "@/lib/reports";
import { makeXlsx } from "@/lib/xlsx";

/** GET /api/reports/gate-pass?month=2026-09 — gate pass log as .xlsx (staff only). */
export async function GET(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (me.role === "EMPLOYEE") return NextResponse.json({ error: "Staff only" }, { status: 403 });

  const month = req.nextUrl.searchParams.get("month") || currentMonth();
  const { label, rows } = await buildGatePassLog(me.companyId, month);

  const buf = await makeXlsx({
    title: `Gate Pass Log — ${label}`,
    subtitle: `${rows.length} passes (all statuses) · ✓ = re-entry verified at gate · ${me.companyName}`,
    sheetName: "Gate passes",
    columns: [
      { header: "Date", width: 12 },
      { header: "Employee", width: 24 },
      { header: "Code", width: 9 },
      { header: "Department", width: 16 },
      { header: "Exit", width: 8 },
      { header: "Return", width: 9 },
      { header: "Reason", width: 34 },
      { header: "Status", width: 11 },
      { header: "Verified", width: 9 },
    ],
    rows: rows.map((r) => [
      r.dayLabel,
      r.name,
      r.code,
      r.department ?? "",
      r.exitAt,
      r.returnAt ?? "—",
      r.reason ?? "",
      r.status,
      r.verified ? "✓" : "",
    ]),
  });

  return new NextResponse(new Uint8Array(buf), {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="gate-pass-log-${month}.xlsx"`,
    },
  });
}
