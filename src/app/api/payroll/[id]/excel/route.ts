import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { makeXlsx } from "@/lib/xlsx";
import { monthName, fmtINR } from "@/lib/utils";

/** GET /api/payroll/[id]/excel?kind=sheet|register|deductions — staff only. */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (me.role === "EMPLOYEE") return NextResponse.json({ error: "Staff only" }, { status: 403 });

  const { id } = await params;
  const kind = req.nextUrl.searchParams.get("kind") || "sheet";
  const run = await db.payrollRun.findFirst({
    where: { id, companyId: me.companyId },
    include: {
      rows: {
        include: { employee: { include: { department: true } } },
        orderBy: { employee: { code: "asc" } },
      },
    },
  });
  if (!run) return NextResponse.json({ error: "Not found" }, { status: 404 });
  const label = monthName(run.month);
  const M = run.rows.map((r) => {
    const e = r.employee;
    const name = e.firstName + (e.lastName ? " " + e.lastName : "");
    const monthly = e.salaryType !== "DAILY";
    const fullBase = monthly ? r.baseAmount + r.deductions : r.baseAmount;
    return { r, e, name, monthly, fullBase, dept: e.department?.name ?? "" };
  });

  let buf: Buffer, filename: string;
  if (kind === "register") {
    buf = await makeXlsx({
      title: `Salary Register — ${label}`,
      subtitle: `${run.rows.length} employees · ${me.companyName} · status ${run.status}`,
      sheetName: "Register",
      columns: [
        { header: "Code", width: 10 }, { header: "Employee", width: 26 }, { header: "Department", width: 16 },
        { header: "Type", width: 10 }, { header: "Payable days", width: 9.5 }, { header: "LOP days", width: 8 },
        { header: "Base ₹", width: 12 }, { header: "LOP ₹", width: 10 },
        { header: "OT ₹", width: 10 }, { header: "Reward +₹", width: 11 },
        { header: "Advance −₹", width: 11 }, { header: "Other −₹", width: 10 },
        { header: "NET ₹", width: 13 },
      ],
      rows: [
        ...M.map(({ r, name, dept, monthly, fullBase }) => [
          r.employee.code, name, dept, monthly ? "MONTHLY" : "DAILY",
          r.payableDays, r.lopDays, fullBase, r.deductions, r.otAmount, r.otherEarning,
          r.advanceRecover, r.otherDeduction, r.netPay,
        ] as (string | number)[]),
        ["", "TOTAL", "", "", "", "", "", "", "", "", "", "", M.reduce((a, m) => a + m.r.netPay, 0)] as (string | number)[],
      ],
    });
    filename = `salary-register-${run.month}.xlsx`;
  } else if (kind === "deductions") {
    buf = await makeXlsx({
      title: `Deductions & OT — ${label}`,
      subtitle: `Advance ledger + OT detail · ${me.companyName}`,
      sheetName: "Deductions",
      columns: [
        { header: "Code", width: 10 }, { header: "Employee", width: 26 },
        { header: "OT hrs", width: 8 }, { header: "OT rate ₹/hr", width: 10 }, { header: "OT ₹", width: 10 },
        { header: "LOP days", width: 8 }, { header: "LOP ₹", width: 10 },
        { header: "Advance −₹", width: 11 }, { header: "Other −₹", width: 10 },
        { header: "Notes", width: 34 },
      ],
      rows: M.map(({ r, name }) => [
        r.employee.code, name, r.otHours || "", r.otHours ? r.otRate : "", r.otAmount || "",
        r.lopDays || "", r.deductions || "", r.advanceRecover || "", r.otherDeduction || "",
        [r.otherEarning ? `+${fmtINR(r.otherEarning)} ${r.otherEarningNote ?? ""}` : "", r.otherDeductionNote ?? ""].filter(Boolean).join(" · "),
      ] as (string | number)[]),
    });
    filename = `payroll-deductions-ot-${run.month}.xlsx`;
  } else {
    // salary sheet — bank disbursement
    buf = await makeXlsx({
      title: `Salary Sheet (bank / cash) — ${label}`,
      subtitle: `Net payable · ${me.companyName}`,
      sheetName: "Salary sheet",
      columns: [
        { header: "Code", width: 10 }, { header: "Employee", width: 26 }, { header: "Bank account", width: 18 },
        { header: "IFSC", width: 13 }, { header: "Mode", width: 8 }, { header: "NET ₹", width: 13 },
      ],
      rows: [
        ...M.map(({ r, e, name }) => [e.code, name, e.bankAccount ?? "", e.ifsc ?? "", r.paymentMode, r.netPay] as (string | number)[]),
        ["", "TOTAL", "", "", "", M.reduce((a, m) => a + m.r.netPay, 0)] as (string | number)[],
      ],
    });
    filename = `salary-sheet-${run.month}.xlsx`;
  }

  return new NextResponse(buf as BodyInit, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}
