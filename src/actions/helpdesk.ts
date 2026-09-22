"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser, requireStaff } from "@/lib/auth";
import type { ActionState } from "./auth";

const CATEGORIES = ["MACHINE", "SALARY", "UNIFORM", "CANTEEN", "SAFETY", "OTHER"] as const;
type Category = (typeof CATEGORIES)[number];

export async function createTicketAction(category: string, subject: string, body: string): Promise<ActionState & { id?: string }> {
  const me = await requireUser();
  if (!me.employeeId) return { error: "Account link nahi — pehlaan dashboard card ton employee profile naal judo." };
  if (!CATEGORIES.includes(category as Category)) return { error: "Category chuno." };
  if (!subject.trim() || subject.trim().length < 4) return { error: "Subject thoda detail ch likho (4+ chars)." };
  if (!body.trim()) return { error: "Details likho — HR nu poora context chahida." };

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
  return { success: "Ticket create ho gya — HR tak pahunch gya! 📨" , id: ticket.id };
}

export async function replyTicketAction(ticketId: string, body: string): Promise<ActionState> {
  const me = await requireUser();
  if (!body.trim()) return { error: "Reply likho." };
  const t = await db.ticket.findFirst({ where: { id: ticketId, companyId: me.companyId } });
  if (!t) return { error: "Ticket nahi mila." };
  const staff = me.role !== "EMPLOYEE";
  if (!staff && me.employeeId !== t.employeeId) return { error: "Sirf apna ticket." };
  if (t.status === "CLOSED") return { error: "Eh ticket close ho chukka." };

  const isStaff = staff;
  await db.$transaction([
    db.ticketReply.create({ data: { ticketId, isStaff, authorName: me.name, body: body.trim() } }),
    db.ticket.update({
      where: { id: ticketId },
      data: {
        // pehli staff reply te auto IN_PROGRESS; employee reply to RESOLVED → re-open nahi, par status wapas IN_PROGRESS for visibility
        status: isStaff && t.status === "OPEN" ? "IN_PROGRESS" : t.status,
        ...(isStaff ? { staffSeenAt: new Date() } : { employeeSeenAt: new Date() }),
      },
    }),
  ]);
  revalidatePath(`/helpdesk/${ticketId}`);
  revalidatePath("/helpdesk");
  return { success: "Reply bhej ditta ✓" };
}

export async function setTicketStatusAction(ticketId: string, status: string): Promise<ActionState> {
  const me = await requireStaff();
  if (!["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"].includes(status)) return { error: "Status ghalat." };
  const t = await db.ticket.findFirst({ where: { id: ticketId, companyId: me.companyId } });
  if (!t) return { error: "Ticket nahi mila." };
  if (t.status === "CLOSED" && status !== "CLOSED" && me.role !== "ADMIN") return { error: "Sirf ADMIN closed ticket re-open kar sakda." };
  await db.ticket.update({
    where: { id: ticketId },
    data: { status: status as "OPEN" | "IN_PROGRESS" | "RESOLVED" | "CLOSED", staffSeenAt: new Date() },
  });
  revalidatePath(`/helpdesk/${ticketId}`);
  revalidatePath("/helpdesk");
  const label = status === "IN_PROGRESS" ? "In progress" : status.charAt(0) + status.slice(1).toLowerCase();
  return { success: `Status: ${label} ✓` };
}

/** Thread page — viewer da side "seen" mark (unread badging layi). */
export async function markTicketSeenAction(ticketId: string): Promise<void> {
  const me = await requireUser();
  const staff = me.role !== "EMPLOYEE";
  await db.ticket.updateMany({
    where: { id: ticketId, companyId: me.companyId, ...(staff ? {} : { employeeId: me.employeeId ?? "__none__" }) },
    data: staff ? { staffSeenAt: new Date() } : { employeeSeenAt: new Date() },
  });
}
