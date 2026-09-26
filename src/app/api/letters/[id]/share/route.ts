import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";

/**
 * POST /api/letters/:id/share — mint (or reuse) the public token link for a
 * letter I own (or any letter for staff). The link opens the printable
 * letterhead page, same token the web "Share link" button produces.
 */
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;

  const letter = await db.letter.findFirst({
    where: { id, companyId: me.companyId },
    select: { id: true, employeeId: true },
  });
  if (!letter) return jsonError("Letter not found.", 404);
  if (me.role === "EMPLOYEE" && letter.employeeId !== me.employeeId) {
    return jsonError("You can only share your own letters.", 403);
  }

  const link = await db.letterLink.upsert({
    where: { letterId: letter.id },
    update: {},
    create: { letterId: letter.id, companyId: me.companyId },
  });
  const path = `/share/letter/${link.token}`;
  return NextResponse.json({ path, url: new URL(path, req.nextUrl.origin).toString() });
}
