import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";

/** DELETE /api/social/:id — author, or any ADMIN/HR (moderation). */
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;
  const post = await db.socialPost.findFirst({ where: { id, companyId: me.companyId } });
  if (!post) return jsonError("Post not found.", 404);
  if (post.authorId !== me.id && me.role === "EMPLOYEE") return jsonError("You can only delete your own posts.", 403);
  await db.socialPost.delete({ where: { id } });
  return NextResponse.json({ ok: true });
}
