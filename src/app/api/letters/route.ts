import { NextRequest, NextResponse } from "next/server";
import { apiUser, unauthorized } from "@/lib/api-auth";
import { db } from "@/lib/db";
import { t, type Lang } from "@/lib/i18n";
import { displayRef, LETTER_TYPE_LABELS } from "@/lib/letter-doc";

export const dynamic = "force-dynamic";

/**
 * GET /api/letters — mobile "My Letters" list.
 * Employees see their own letters only; staff see every letter of the
 * company (same rule as the web /letters page).
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const staff = me.role !== "EMPLOYEE";
  if (!staff && !me.employeeId) return NextResponse.json({ linked: false, staff, letters: [] });

  const lang: Lang = req.nextUrl.searchParams.get("lang") === "pa" ? "pa" : "en";
  const rows = await db.letter.findMany({
    where: { companyId: me.companyId, ...(staff ? {} : { employeeId: me.employeeId as string }) },
    include: { employee: { select: { id: true, code: true, firstName: true, lastName: true } } },
    orderBy: { createdAt: "desc" },
  });

  return NextResponse.json({
    linked: true,
    staff,
    letters: rows.map((l) => ({
      id: l.id,
      serial: l.serial,
      ref: displayRef(l.serial, l.employee.code),
      type: l.type,
      typeLabel: t(lang, LETTER_TYPE_LABELS[l.type] ?? l.type),
      issuedTo: l.issuedTo,
      createdAt: l.createdAt,
      employee: staff
        ? { id: l.employee.id, code: l.employee.code, name: `${l.employee.firstName} ${l.employee.lastName}` }
        : null,
    })),
  });
}
