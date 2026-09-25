import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { getPerms } from "@/lib/permissions";
import { PERM_KEYS } from "@/actions/_perm-keys";

export const dynamic = "force-dynamic";

type PermKey = (typeof PERM_KEYS)[number];

async function loadEmployee(companyId: string, id: string) {
  return db.employee.findFirst({
    where: { id, companyId },
    select: { id: true, code: true, firstName: true, lastName: true, photoExt: true, department: { select: { name: true } } },
  });
}

function shapeEmp(e: NonNullable<Awaited<ReturnType<typeof loadEmployee>>>) {
  return {
    id: e.id,
    code: e.code,
    name: `${e.firstName} ${e.lastName}`.trim(),
    dept: e.department?.name ?? null,
    photo: e.photoExt ? `/api/photo/${e.id}` : null,
  };
}

/** GET /api/permissions/:employeeId — the 6 feature toggles (ADMIN only). */
export async function GET(req: NextRequest, { params }: { params: Promise<{ employeeId: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role !== "ADMIN") return jsonError("Super admin only.", 403);
  const { employeeId } = await params;
  const emp = await loadEmployee(me.companyId, employeeId);
  if (!emp) return jsonError("Employee not found.", 404);
  return NextResponse.json({ employee: shapeEmp(emp), perms: await getPerms(emp.id) });
}

/**
 * PUT /api/permissions/:employeeId {key, allowed} — flip ONE toggle (ADMIN only).
 * Takes effect on their phone at the next /api/auth/me refresh; every write
 * endpoint also re-checks server-side, so it is enforced immediately.
 */
export async function PUT(req: NextRequest, { params }: { params: Promise<{ employeeId: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  if (me.role !== "ADMIN") return jsonError("Super admin only.", 403);
  const { employeeId } = await params;
  const emp = await loadEmployee(me.companyId, employeeId);
  if (!emp) return jsonError("Employee not found.", 404);

  const b = await req.json().catch(() => null);
  const key = String(b?.key ?? "");
  if (!(PERM_KEYS as readonly string[]).includes(key)) return jsonError("Unknown permission key.");
  if (typeof b?.allowed !== "boolean") return jsonError("allowed must be true or false.");
  const k = key as PermKey;

  await db.employeePermission.upsert({
    where: { employeeId: emp.id },
    create: { companyId: me.companyId, employeeId: emp.id, [k]: b.allowed },
    update: { [k]: b.allowed },
  });
  return NextResponse.json({ employee: shapeEmp(emp), perms: await getPerms(emp.id) });
}
