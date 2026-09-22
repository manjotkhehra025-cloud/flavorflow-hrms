import { NextRequest, NextResponse } from "next/server";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { uploadDir } from "@/lib/storage";

/** GET /api/selfie/selfie-<empId>-<yyyymmdd>.jpg — owner or staff only. */
export async function GET(req: NextRequest, { params }: { params: Promise<{ name: string }> }) {
  const { name } = await params;
  if (!/^selfie-[a-zA-Z0-9]+-\d{8}\.jpg$/.test(name)) return new NextResponse("Not found", { status: 404 });

  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me) return new NextResponse("Unauthorized", { status: 401 });

  const employeeId = name.split("-")[1];
  if (me.role === "EMPLOYEE" && me.employeeId !== employeeId) {
    return new NextResponse("Forbidden", { status: 403 });
  }
  // company scope check: employee of the selfie must belong to my company
  const emp = await db.employee.findFirst({ where: { id: employeeId, companyId: me.companyId }, select: { id: true } });
  if (!emp) return new NextResponse("Not found", { status: 404 });

  const buf = await readFile(join(uploadDir(), name)).catch(() => null);
  if (!buf) return new NextResponse("Not found", { status: 404 });
  return new NextResponse(new Uint8Array(buf), {
    headers: { "Content-Type": "image/jpeg", "Cache-Control": "private, max-age=3600" },
  });
}
