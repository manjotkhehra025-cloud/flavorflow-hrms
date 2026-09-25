import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import type { SessionUser } from "@/lib/auth";
import type { TicketStatus } from "@prisma/client";

export const dynamic = "force-dynamic";

const STATUSES = ["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"] as const;

/** Staff see every ticket in the company; employees only their own. */
async function loadTicket(me: SessionUser, id: string) {
  const t = await db.ticket.findFirst({
    where: { id, companyId: me.companyId },
    include: {
      employee: { select: { firstName: true, lastName: true, code: true } },
      replies: { orderBy: { createdAt: "asc" } },
    },
  });
  if (!t) return null;
  if (me.role === "EMPLOYEE" && t.employeeId !== me.employeeId) return null;
  return t;
}

/** GET /api/helpdesk/:id — thread (oldest first); marks my side as seen. */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;
  const t = await loadTicket(me, id);
  if (!t) return jsonError("Ticket not found.", 404);

  const staff = me.role !== "EMPLOYEE";
  // Staff viewing their OWN ticket act as the employee side (matches web thread page).
  const staffSide = staff && t.employeeId !== me.employeeId;
  await db.ticket.update({ where: { id }, data: staffSide ? { staffSeenAt: new Date() } : { employeeSeenAt: new Date() } });

  return NextResponse.json({
    ticket: {
      id: t.id,
      category: t.category,
      subject: t.subject,
      status: t.status,
      createdAt: t.createdAt,
      employee: { name: `${t.employee.firstName} ${t.employee.lastName}`.trim(), code: t.employee.code },
      canReply: t.status !== "CLOSED",
      canSetStatus: staff,
      staffSide,
      replies: t.replies.map((r) => ({ id: r.id, body: r.body, isStaff: r.isStaff, author: r.authorName, at: r.createdAt })),
    },
  });
}

/** POST /api/helpdesk/:id {body} — reply. First staff reply flips OPEN → IN_PROGRESS. */
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;
  const t = await loadTicket(me, id);
  if (!t) return jsonError("Ticket not found.", 404);
  if (t.status === "CLOSED") return jsonError("This ticket is closed.", 409);
  const b = await req.json().catch(() => null);
  const body = String(b?.body ?? "").trim();
  if (!body) return jsonError("Write a reply first.");
  if (body.length > 2000) return jsonError("Reply too long (max 2000 characters).");

  const isStaff = me.role !== "EMPLOYEE";
  const [reply] = await db.$transaction([
    db.ticketReply.create({ data: { ticketId: id, isStaff, authorName: me.name, body } }),
    db.ticket.update({
      where: { id },
      data: {
        status: isStaff && t.status === "OPEN" ? "IN_PROGRESS" : t.status,
        ...(isStaff ? { staffSeenAt: new Date() } : { employeeSeenAt: new Date() }),
      },
    }),
  ]);
  return NextResponse.json(
    { reply: { id: reply.id, body: reply.body, isStaff: reply.isStaff, author: reply.authorName, at: reply.createdAt } },
    { status: 201 },
  );
}

/** PATCH /api/helpdesk/:id {status} — ADMIN/HR. Only ADMIN may re-open a CLOSED ticket. */
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role === "EMPLOYEE") return jsonError("Only HR / admin can change ticket status.", 403);
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const status = String(b?.status ?? "");
  if (!(STATUSES as readonly string[]).includes(status)) return jsonError("Invalid status.");
  const t = await db.ticket.findFirst({ where: { id, companyId: me.companyId }, select: { status: true } });
  if (!t) return jsonError("Ticket not found.", 404);
  if (t.status === "CLOSED" && status !== "CLOSED" && me.role !== "ADMIN") {
    return jsonError("Only an ADMIN can re-open a closed ticket.", 403);
  }
  await db.ticket.update({ where: { id }, data: { status: status as TicketStatus, staffSeenAt: new Date() } });
  return NextResponse.json({ ok: true, status });
}
