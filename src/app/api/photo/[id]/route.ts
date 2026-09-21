import { readFile } from "node:fs/promises";
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { photoPath } from "@/lib/storage";

export const dynamic = "force-dynamic";

const MIME: Record<string, string> = { jpg: "image/jpeg", png: "image/png", webp: "image/webp" };

export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[a-z0-9]+$/i.test(id)) return new NextResponse(null, { status: 400 });

  const emp = await db.employee.findFirst({ where: { id }, select: { photoExt: true } });
  if (!emp?.photoExt) return new NextResponse(null, { status: 404 });

  try {
    const buf = await readFile(photoPath(id, emp.photoExt));
    return new NextResponse(buf, {
      headers: {
        "Content-Type": MIME[emp.photoExt] ?? "image/jpeg",
        "Cache-Control": "public, max-age=86400, must-revalidate",
      },
    });
  } catch {
    return new NextResponse(null, { status: 404 });
  }
}
