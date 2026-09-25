import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";

/** POST /api/social/:id/like — toggle my like; returns the fresh state. */
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;
  const post = await db.socialPost.findFirst({ where: { id, companyId: me.companyId }, select: { id: true } });
  if (!post) return jsonError("Post not found.", 404);

  const existing = await db.postLike.findUnique({ where: { postId_userId: { postId: id, userId: me.id } } });
  if (existing) await db.postLike.delete({ where: { id: existing.id } });
  else await db.postLike.create({ data: { postId: id, userId: me.id } }).catch(() => null); // double-tap race → unique hit, fine

  const likes = await db.postLike.count({ where: { postId: id } });
  return NextResponse.json({ liked: !existing, likes });
}
