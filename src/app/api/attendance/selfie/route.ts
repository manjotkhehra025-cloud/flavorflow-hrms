import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken } from "@/lib/auth";
import { db } from "@/lib/db";
import { uploadDir } from "@/lib/storage";
import { join } from "node:path";
import { mkdir, writeFile } from "node:fs/promises";

/** POST /api/attendance/selfie — employee uploads today's punch selfie (compressed JPEG). */
export async function POST(req: NextRequest) {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const me = (await getUserFromToken(bearer)) ?? (await getSessionUser());
  if (!me?.employeeId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  let body: { dataUrl?: string };
  try { body = await req.json(); } catch { return NextResponse.json({ error: "Bad data" }, { status: 400 }); }
  const dataUrl = String(body.dataUrl ?? "");
  const m = dataUrl.match(/^data:image\/jpeg;base64,([A-Za-z0-9+/=]+)$/);
  if (!m) return NextResponse.json({ error: "JPEG data-URL only" }, { status: 400 });
  const buf = Buffer.from(m[1], "base64");
  if (buf.length > 900_000) return NextResponse.json({ error: "Selfie too large" }, { status: 413 });
  if (buf.length < 2048) return NextResponse.json({ error: "Empty capture" }, { status: 400 });

  const date = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const name = `selfie-${me.employeeId}-${date}.jpg`;
  await mkdir(uploadDir(), { recursive: true });
  await writeFile(join(uploadDir(), name), buf);
  return NextResponse.json({ path: `/api/selfie/${name}` });
}
