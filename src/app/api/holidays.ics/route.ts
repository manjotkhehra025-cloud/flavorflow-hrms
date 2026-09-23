import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { getSessionUser } from "@/lib/auth";

/** One-tap .ics export of this year's holidays for phone calendars. */
export async function GET() {
  const me = await getSessionUser();
  if (!me) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const year = new Date().getUTCFullYear();
  const holidays = await db.holiday.findMany({
    where: { companyId: me.companyId, date: { gte: new Date(Date.UTC(year, 0, 1)), lte: new Date(Date.UTC(year, 11, 31)) } },
    orderBy: { date: "asc" },
  });

  const fmt = (d: Date) => d.toISOString().slice(0, 10).replace(/-/g, "");
  const esc = (s: string) => s.replace(/([,;\\])/g, "\\$1").replace(/\n/g, "\\n");
  const events = holidays.map((h) => [
    "BEGIN:VEVENT",
    `UID:${h.id}@hrmate`,
    `DTSTAMP:${new Date().toISOString().replace(/[-:]|\.\d+/g, "").slice(0, 15)}Z`,
    `DTSTART;VALUE=DATE:${fmt(h.date)}`,
    `DTEND;VALUE=DATE:${fmt(new Date(h.date.getTime() + 86400000))}`,
    `SUMMARY:${esc(h.name)} (${esc(me.companyName)})`,
    "END:VEVENT",
  ].join("\r\n"));

  const ics = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//HRMate//Holidays//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH", ...events.length ? [events] : [], "END:VCALENDAR"]
    .flat()
    .filter(Boolean)
    .join("\r\n");

  return new NextResponse(ics, {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": `attachment; filename="holidays-${year}.ics"`,
    },
  });
}
