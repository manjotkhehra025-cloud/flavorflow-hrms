import { NextRequest, NextResponse } from "next/server";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { db } from "@/lib/db";
import { buildLetterDoc } from "@/lib/letter-doc";
import type { Lang } from "@/lib/i18n";

export const dynamic = "force-dynamic";

/**
 * GET /api/letters/:id — the full letter document (letterhead sheet) for the
 * mobile viewer. Same ownership rule as the web page: owner employee or staff.
 * `?lang=pa` returns the Punjabi prose segments.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;

  const letter = await db.letter.findFirst({
    where: { id, companyId: me.companyId },
    include: { employee: { include: { department: true, designation: true } }, company: true },
  });
  if (!letter) return jsonError("Letter not found.", 404);
  if (me.role === "EMPLOYEE" && letter.employeeId !== me.employeeId) return jsonError("Letter not found.", 404);

  const lang: Lang = req.nextUrl.searchParams.get("lang") === "pa" ? "pa" : "en";
  return NextResponse.json({ letter: buildLetterDoc(letter, lang) });
}
