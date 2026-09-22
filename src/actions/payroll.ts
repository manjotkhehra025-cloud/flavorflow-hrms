"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireStaff } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import { calculatePayroll } from "@/lib/payroll";
import type { ActionState } from "./auth";

function toInt(v: unknown): number | null {
  const n = parseInt(String(v ?? "").replace(/[^\d-]/g, ""), 10);
  return Number.isFinite(n) && n >= 0 ? n : null;
}
function toFloat(v: unknown): number | null {
  const n = parseFloat(String(v ?? ""));
  return Number.isFinite(n) && n >= 0 ? n : null;
}

/** Staff: compute payroll for a month → creates/overwrites a DRAFT run with rows. */
export async function computePayrollAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const month = String(formData.get("month") ?? "");
  if (!/^\d{4}-\d{2}$/.test(month)) return { error: await bt("Invalid month.") };

  const existing = await db.payrollRun.findUnique({
    where: { companyId_month: { companyId: me.companyId, month } },
  });
  if (existing && existing.status !== "DRAFT") {
    return { error: await bt("This month's payroll is already approved — it cannot be recomputed.") };
  }

  const calc = await calculatePayroll(me.companyId, month);
  if (calc.rows.length === 0) {
    return { error: await bt("No employee has a salary set yet — open a profile and add Pay & advances first.") };
  }

  const run = await db.$transaction(async (tx) => {
    const run = existing
      ? await tx.payrollRun.update({ where: { id: existing.id }, data: {} })
      : await tx.payrollRun.create({ data: { companyId: me.companyId, month, createdById: me.id } });
    await tx.payrollRow.deleteMany({ where: { runId: run.id } });
    await tx.payrollRow.createMany({
      data: calc.rows.map((r) => ({
        runId: run.id,
        employeeId: r.employeeId,
        payableDays: r.payableDays,
        presentDays: r.presentDays,
        absentDays: r.absentDays,
        leaveDays: r.leaveDays,
        offDays: r.offDays,
        lopDays: r.lopDays,
        baseAmount: r.baseAmount,
        otHours: r.otHours,
        otRate: r.otRate,
        otAmount: r.otAmount,
        deductions: r.deductions,
        advanceRecover: r.advanceRecover,
        otherDeduction: r.otherDeduction,
        otherEarning: r.otherEarning,
        netPay: r.netPay,
      })),
    });
    return run;
  });
  revalidatePath("/payroll");
  revalidatePath(`/payroll/${run.id}`);
  return { success: (await bt("Payroll computed for {month} ({n} employees)."))!.replace("{month}", month).replace("{n}", String(calc.rows.length)) };
}

type RowEdit = { id: string; otHours: number; otherDeduction: number; otherDeductionNote: string | null; otherEarning: number; otherEarningNote: string | null; advanceRecover: number };

/** Staff: save manual adjustments to DRAFT rows (OT hours, ± amounts, advance recovery) and re-derive net pay. */
export async function saveRowAdjustmentsAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const runId = String(formData.get("runId") ?? "");
  const run = await db.payrollRun.findFirst({ where: { id: runId, companyId: me.companyId } });
  if (!run) return { error: await bt("Payroll run not found.") };
  if (run.status !== "DRAFT") return { error: await bt("Only DRAFT payroll can be edited.") };

  let edits: RowEdit[];
  try { edits = JSON.parse(String(formData.get("edits") ?? "[]")); } catch { return { error: await bt("Bad data.") }; }

  const rows = await db.payrollRow.findMany({ where: { runId: run.id }, include: { employee: { include: { advances: true } } } });
  const rowMap = new Map(rows.map((r) => [r.id, r]));

  for (const e of edits) {
    const row = rowMap.get(e.id);
    if (!row) continue;
    const otHours = Math.min(toFloat(e.otHours) ?? 0, 200);
    const otherDeduction = Math.min(toInt(e.otherDeduction) ?? 0, row.baseAmount + row.otAmount + 100000);
    const otherEarning = Math.min(toInt(e.otherEarning) ?? 0, 100000);
    const advBalance = (row.employee.advances ?? []).reduce((s, a) => s + (a.amount - a.repaid), 0);
    const advanceRecover = Math.min(toInt(e.advanceRecover) ?? 0, advBalance);

    const otAmount = Math.round(otHours * row.otRate);
    const net = Math.max(0, row.baseAmount + otAmount + otherEarning - advanceRecover - otherDeduction);
    await db.payrollRow.update({
      where: { id: row.id },
      data: {
        otHours, otAmount,
        otherDeduction, otherDeductionNote: (e.otherDeductionNote ?? "").trim() || null,
        otherEarning, otherEarningNote: (e.otherEarningNote ?? "").trim() || null,
        advanceRecover,
        netPay: net,
      },
    });
  }
  revalidatePath(`/payroll/${run.id}`);
  return { success: await bt("Adjustments saved. Recheck net pay, then Approve & lock.") };
}

/** Staff: DRAFT → LOCKED (approve + lock in one tap; applies advance recoveries). */
export async function approveLockPayrollAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireStaff();
  const runId = String(formData.get("runId") ?? "");
  const run = await db.payrollRun.findFirst({ where: { id: runId, companyId: me.companyId } });
  if (!run) return { error: await bt("Payroll run not found.") };
  if (run.status !== "DRAFT") return { error: await bt("Payroll is already locked.") };

  const rows = await db.payrollRow.findMany({ where: { runId: run.id }, include: { employee: { include: { advances: { orderBy: { givenDate: "asc" } } } } } });

  await db.$transaction(async (tx) => {
    // apply advance recoveries FIFO across open advances
    for (const row of rows) {
      let need = row.advanceRecover;
      if (need <= 0) continue;
      for (const adv of row.employee.advances) {
        if (need <= 0) break;
        const open = adv.amount - adv.repaid;
        if (open <= 0) continue;
        const take = Math.min(open, need);
        await tx.advance.update({ where: { id: adv.id }, data: { repaid: { increment: take } } });
        need -= take;
      }
    }
    await tx.payrollRun.update({
      where: { id: run.id },
      data: { status: "LOCKED", approvedById: me.id, approvedAt: new Date(), lockedById: me.id, lockedAt: new Date() },
    });
  });
  revalidatePath("/payroll");
  revalidatePath(`/payroll/${run.id}`);
  return { success: await bt("Payroll approved & locked — payslips are now visible to employees ✔") };
}
