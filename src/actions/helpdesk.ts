"use server";
import { bt } from "@/lib/i18n";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import type { ActionState } from "./auth";

const CATEGORIES = ["MACHINE", "SALARY", "UNIFORM", "CANTEEN", "SAFETY", "OTHER"] as const;
type Category = (typeof CATEGORIES)[number];

export async function createTicketAction(category: string, subject: string, body: string): Promise<ActionState & { id?: string }> {
  const me = await requireUser();
  if (!me.employeeId) return { error: await bt("Account not linked — link your login to an employee profile from the dashboard card first.") };
  if (!CATEGORIES.includes(category as Category)) return { error: await bt("Please pick a category.") };
  if (!subject.trim() || subject.trim().length < 4) return { error: await bt("Please write a slightly detailed subject (4+ characters).") };
  if (!body.trim()) return { error: await bt("Please add details — HR needs the full context.") };

  const ticket = await db.ticket.create({
    data: {
      companyId: me.companyId,
      employeeId: me.employeeId,
      category: category as Category,
      subject: subject.trim(),
      employeeSeenAt: new Date(),
      replies: { create: { isStaff: me.role !== "EMPLOYEE", authorName: me.name, body: body.trim() } },
    },
  });
  revalidatePath("/helpdesk");
  return { success: await bt("Ticket created — delivered to HR! 📨") , id: ticket.id };
}

export async function replyTicketAction(ticketId: string, body: string): Promise<ActionState> {
  const me = await requireUser();
  if (!body.trim()) return { error: await bt("Write a reply first.") };
  const t = await db.ticket.findFirst({ where: { id: ticketId, companyId: me.companyId } });
  if (!t) return { error: await bt("Ticket not found.") };
  const staff = me.role !== "EMPLOYEE";
  if (!staff && me.employeeId !== t.employeeId) return { error: await bt("You can only open your own tickets.") };
  if (t.status === "CLOSED") return { error: await bt("This ticket is closed.") };

  const isStaff = staff;
  await db.$transaction([
    db.ticketReply.create({ data: { ticketId, isStaff, authorName: me.name, body: body.trim() } }),
    db.ticket.update({
      where: { id: ticketId },
      data: {
        // first staff reply auto-marks IN_PROGRESS; employee replies keep status as-is
        status: isStaff && t.status === "OPEN" ? "IN_PROGRESS" : t.status,
        ...(isStaff ? { staffSeenAt: new Date() } : { employeeSeenAt: new Date() }),
      },
    }),
  ]);
  revalidatePath(`/helpdesk/${ticketId}`);
  revalidatePath("/helpdesk");
  return { success: await bt("Reply sent ✓") };
}

export async function setTicketStatusAction(ticketId: string, status: string): Promise<ActionState> {
  const me = await requireStaff();
  if (!["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"].includes(status)) return { error: await bt("Invalid status.") };
  const t = await db.ticket.findFirst({ where: { id: ticketId, companyId: me.companyId } });
  if (!t) return { error: await bt("Ticket not found.") };
  if (t.status === "CLOSED" && status !== "CLOSED" && me.role !== "ADMIN") return { error: await bt("Only an ADMIN can re-open a closed ticket.") };
  await db.ticket.update({
    where: { id: ticketId },
    data: { status: status as "OPEN" | "IN_PROGRESS" | "RESOLVED" | "CLOSED", staffSeenAt: new Date() },
  });
  revalidatePath(`/helpdesk/${ticketId}`);
  revalidatePath("/helpdesk");
  const label = status === "IN_PROGRESS" ? "In progress" : status.charAt(0) + status.slice(1).toLowerCase();
  return { success: `Status: ${label} ✓` };
}

/** Thread page — marks the viewer's side as seen (for unread badging). */
export async function markTicketSeenAction(ticketId: string): Promise<void> {
  const me = await requireUser();
  const staff = me.role !== "EMPLOYEE";
  await db.ticket.updateMany({
    where: { id: ticketId, companyId: me.companyId, ...(staff ? {} : { employeeId: me.employeeId ?? "__none__" }) },
    data: staff ? { staffSeenAt: new Date() } : { employeeSeenAt: new Date() },
  });
}
