import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { timeAgo } from "@/lib/utils";

async function findPost(id: string, companyId: string) {
  return db.socialPost.findFirst({ where: { id, companyId }, select: { id: true } });
}

/** GET /api/social/:id/comments — full thread, oldest first. */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;
  if (!(await findPost(id, me.companyId))) return jsonError("Post not found.", 404);
  const comments = await db.postComment.findMany({
    where: { postId: id },
    orderBy: { createdAt: "asc" },
    include: { user: { select: { name: true } } },
  });
  return NextResponse.json({
    comments: comments.map((c) => ({ id: c.id, body: c.body, user: c.user.name, at: timeAgo(c.createdAt), own: c.userId === me.id })),
  });
}

/** POST /api/social/:id/comments {body} — anyone signed in may comment (same as web). */
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const { id } = await params;
  if (!(await findPost(id, me.companyId))) return jsonError("Post not found.", 404);
  const payload = await req.json().catch(() => null);
  const body = String(payload?.body ?? "").trim();
  if (!body) return jsonError("Empty comment.");
  if (body.length > 400) return jsonError("Comment too long.");
  const c = await db.postComment.create({ data: { postId: id, userId: me.id, body } });
  return NextResponse.json({ comment: { id: c.id, body: c.body, user: me.name, at: timeAgo(c.createdAt), own: true } }, { status: 201 });
}
