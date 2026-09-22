"use client";

import { useEffect } from "react";
import { markTicketSeenAction } from "@/actions/helpdesk";

export function MarkSeen({ ticketId }: { ticketId: string }) {
  useEffect(() => {
    markTicketSeenAction(ticketId).catch(() => {});
  }, [ticketId]);
  return null;
}
