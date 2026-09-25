import { db } from "@/lib/db";
import { canDecideFor } from "@/lib/approve-routing";
import { notifyDecision } from "@/lib/push";
import type { SessionUser } from "@/lib/auth";

export type DecideKind = "leave" | "gate" | "punch" | "swap";

export type DecideOk = {
  ok: true;
  kind: DecideKind;
  id: string;
  approve: boolean;
  employeeId: string;
  /** Short human summary for the decision push / bell. */
  summary: string;
};

export type DecideFail = { ok: false; status: 400 | 403 | 404; error: string };

const ALREADY: DecideFail = { ok: false, status: 404, error: "Not found or already decided." };

const empInc = { department: { include: { parent: true } }, designation: true } as const;

/**
 * Single decide path for web actions AND /api/approvals/decide.
 * Approving a manual punch also writes the attendance row — the mobile API
 * used to flip status only, so a phone approval never fixed the timesheet.
 */
async function decideInner(
  me: SessionUser,
  input: { kind: string; id: string; approve: boolean },
): Promise<DecideOk | DecideFail> {
  const kind = input.kind as DecideKind;
  const id = input.id;
  if (!["leave", "gate", "punch", "swap"].includes(kind) || !id) {
    return { ok: false, status: 400, error: "Bad request." };
  }

  const decidedAt = new Date();
  const status = input.approve ? "APPROVED" : "REJECTED";

  if (kind === "leave") {
    const row = await db.leaveRequest.findFirst({
      where: { id, companyId: me.companyId, status: "PENDING" },
      include: { employee: { include: empInc }, leaveType: true },
    });
    if (!row) return { ok: false, status: 404, error: "Not found or already decided." };
    if (!(await canDecideFor(me, row.employee as never))) {
      return { ok: false, status: 403, error: "Not your approval to take." };
    }
    // Guarded on PENDING: two approvers tapping at once → only the first wins
    // (no double push / double attendance write).
    const won = await db.leaveRequest.updateMany({
      where: { id, companyId: me.companyId, status: "PENDING" },
      data: { status, approverId: me.id, decidedAt },
    });
    if (won.count === 0) return ALREADY;
    return {
      ok: true,
      kind,
      id,
      approve: input.approve,
      employeeId: row.employeeId,
      summary: `${row.leaveType.name} · ${row.days}${row.halfDay ? " (½)" : ""}d`,
    };
  }

  if (kind === "gate") {
    const row = await db.gatePass.findFirst({
      where: { id, companyId: me.companyId, status: "PENDING" },
      include: { employee: { include: empInc } },
    });
    if (!row) return { ok: false, status: 404, error: "Not found or already decided." };
    if (!(await canDecideFor(me, row.employee as never))) {
      return { ok: false, status: 403, error: "Not your approval to take." };
    }
    // Guarded on PENDING: two approvers tapping at once → only the first wins
    // (no double push / double attendance write).
    const won = await db.gatePass.updateMany({
      where: { id, companyId: me.companyId, status: "PENDING" },
      data: { status, approverId: me.id, decidedAt },
    });
    if (won.count === 0) return ALREADY;
    return {
      ok: true,
      kind,
      id,
      approve: input.approve,
      employeeId: row.employeeId,
      summary: row.exitAt,
    };
  }

  if (kind === "punch") {
    const row = await db.punchRequest.findFirst({
      where: { id, companyId: me.companyId, status: "PENDING" },
      include: { employee: { include: empInc } },
    });
    if (!row) return { ok: false, status: 404, error: "Not found or already decided." };
    if (!(await canDecideFor(me, row.employee as never))) {
      return { ok: false, status: 403, error: "Not your approval to take." };
    }
    // Guarded on PENDING: two approvers tapping at once → only the first wins
    // (no double push / double attendance write).
    const won = await db.punchRequest.updateMany({
      where: { id, companyId: me.companyId, status: "PENDING" },
      data: { status, approverId: me.id, decidedAt },
    });
    if (won.count === 0) return ALREADY;
    if (input.approve && row.type !== "OT" && row.time) {
      await applyApprovedManualPunch(me.companyId, row);
    }
    const label = row.type === "OT" ? `OT ${row.hours ?? ""}h` : `${row.type === "MANUAL_IN" ? "In" : "Out"} ${row.time ?? ""}`;
    return {
      ok: true,
      kind,
      id,
      approve: input.approve,
      employeeId: row.employeeId,
      summary: label.trim(),
    };
  }

  const swap = await db.shiftSwapRequest.findFirst({
    where: { id, companyId: me.companyId, status: "PENDING" },
    include: { requester: { include: empInc }, peer: true },
  });
  if (!swap) return { ok: false, status: 404, error: "Not found or already decided." };
  if (!(await canDecideFor(me, swap.requester as never))) {
    return { ok: false, status: 403, error: "Not your approval to take." };
  }
  // Guarded on PENDING: two approvers tapping at once → only the first wins
  // (no double push / double attendance write).
  const won = await db.shiftSwapRequest.updateMany({
    where: { id, companyId: me.companyId, status: "PENDING" },
    data: { status, decidedAt },
  });
  if (won.count === 0) return ALREADY;
  return {
    ok: true,
    kind,
    id,
    approve: input.approve,
    employeeId: swap.requesterId,
    summary: `${swap.requester.firstName} ↔ ${swap.peer.firstName}`,
  };
}

export async function decideApproval(
  me: SessionUser,
  input: { kind: string; id: string; approve: boolean },
): Promise<DecideOk | DecideFail> {
  const result = await decideInner(me, input);
  if (result.ok) notifyDecision(result.employeeId, result.kind, result.approve, result.summary);
  return result;
}

/** Write an approved MANUAL_IN / MANUAL_OUT onto the attendance row (IST stamp). */
async function applyApprovedManualPunch(
  companyId: string,
  req: { employeeId: string; date: Date; time: string | null; type: string },
) {
  if (!req.time) return;
  const stamp = new Date(`${req.date.toISOString().slice(0, 10)}T${req.time}:00+05:30`);
  const isIn = req.type === "MANUAL_IN";
  // upsert (not find → create): a live punch landing at the same moment can't
  // trip the (employeeId, date) unique key.
  await db.attendance.upsert({
    where: { employeeId_date: { employeeId: req.employeeId, date: req.date } },
    create: {
      companyId,
      employeeId: req.employeeId,
      date: req.date,
      ...(isIn ? { checkIn: stamp } : { checkOut: stamp }),
      status: "PRESENT",
      note: isIn ? "Manual check-in approved" : "Manual check-out approved",
    },
    update: {
      ...(isIn ? { checkIn: stamp } : { checkOut: stamp }),
      status: "PRESENT",
      note: isIn ? `Manual check-in → ${req.time} approved` : `Manual check-out → ${req.time} approved`,
    },
  });
}
