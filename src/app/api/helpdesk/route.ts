import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import type { TicketCategory, TicketStatus } from "@prisma/client";

export const dynamic = "force-dynamic";

const CATEGORIES = ["MACHINE", "SALARY", "UNIFORM", "CANTEEN", "SAFETY", "OTHER"] as const;
const STATUSES = ["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"] as const;

type TicketRow = {
  id: string;
  category: string;
  subject: string;
  status: string;
  updatedAt: Date;
  createdAt: Date;
  employeeSeenAt: Date | null;
  staffSeenAt: Date | null;
  employee?: { firstName: string; lastName: string; code: string } | null;
  replies: { body: string; isStaff: boolean; authorName: string; createdAt: Date }[];
};

function shape(t: TicketRow, viewerIsStaffSide: boolean) {
  const last = t.replies[0];
  const seen = viewerIsStaffSide ? t.staffSeenAt : t.employeeSeenAt;
  // unread = the other side wrote after I last looked
  const unread = !!last && last.isStaff !== viewerIsStaffSide && (!seen || last.createdAt > seen);
  return {
    id: t.id,
    category: t.category,
    subject: t.subject,
    status: t.status,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
    unread,
    employee: t.employee ? { name: `${t.employee.firstName} ${t.employee.lastName}`.trim(), code: t.employee.code } : undefined,
    last: last ? { body: last.body.slice(0, 140), isStaff: last.isStaff, author: last.authorName, at: last.createdAt } : null,
  };
}

/**
 * GET /api/helpdesk(?scope=inbox&status=OPEN|IN_PROGRESS|RESOLVED|ALL)
 * Default: my own tickets. ADMIN/HR can pass scope=inbox for the team queue.
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const staff = me.role !== "EMPLOYEE";
  const scope = req.nextUrl.searchParams.get("scope") === "inbox" && staff ? "inbox" : "mine";

  if (scope === "inbox") {
    const f = req.nextUrl.searchParams.get("status") ?? "OPEN";
    const status = (STATUSES as readonly string[]).includes(f) ? (f as TicketStatus) : null;
    const [tickets, counts] = await Promise.all([
      db.ticket.findMany({
        where: { companyId: me.companyId, ...(status ? { status } : {}) },
        include: {
          employee: { select: { firstName: true, lastName: true, code: true } },
          replies: { orderBy: { createdAt: "desc" }, take: 1 },
        },
        orderBy: { updatedAt: "desc" },
        take: 100,
      }),
      db.ticket.groupBy({ by: ["status"], where: { companyId: me.companyId }, _count: { _all: true } }),
    ]);
    return NextResponse.json({
      scope,
      staff,
      counts: Object.fromEntries(STATUSES.map((s) => [s, counts.find((c) => c.status === s)?._count._all ?? 0])),
      tickets: tickets.map((t) => shape(t, true)),
    });
  }

  if (!me.employeeId) return NextResponse.json({ scope, staff, tickets: [], linked: false });
  const tickets = await db.ticket.findMany({
    where: { companyId: me.companyId, employeeId: me.employeeId },
    include: { replies: { orderBy: { createdAt: "desc" }, take: 1 } },
    orderBy: { updatedAt: "desc" },
  });
  return NextResponse.json({ scope, staff, linked: true, tickets: tickets.map((t) => shape(t, false)) });
}

/** POST /api/helpdesk {category, subject, body} — raise a ticket (first message = body). */
export async function POST(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (!me.employeeId) return jsonError("Account not linked — link your login to an employee profile first.");
  const b = await req.json().catch(() => null);
  const category = String(b?.category ?? "");
  const subject = String(b?.subject ?? "").trim();
  const body = String(b?.body ?? "").trim();
  if (!(CATEGORIES as readonly string[]).includes(category)) return jsonError("Please pick a category.");
  if (subject.length < 4) return jsonError("Please write a slightly detailed subject (4+ characters).");
  if (subject.length > 140) return jsonError("Subject too long (max 140 characters).");
  if (!body) return jsonError("Please add details — HR needs the full context.");
  if (body.length > 2000) return jsonError("Details too long (max 2000 characters).");

  const ticket = await db.ticket.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      category: category as TicketCategory,
      subject,
      employeeSeenAt: new Date(),
      replies: { create: { isStaff: me.role !== "EMPLOYEE", authorName: me.name, body } },
    },
    select: { id: true },
  });
  return NextResponse.json({ ticket }, { status: 201 });
}
