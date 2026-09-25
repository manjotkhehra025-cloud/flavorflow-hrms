import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { apiUser, unauthorized, jsonError } from "@/lib/api-auth";
import { getPerms, permDenied } from "@/lib/permissions";
import { timeAgo } from "@/lib/utils";

export const dynamic = "force-dynamic";

const authorInclude = {
  employee: { select: { id: true, photoExt: true, department: { select: { name: true } } } },
} as const;

/**
 * GET /api/social(?before=ISO) — company wall, newest first (30 per page).
 * Each post: author + dept + avatar, like count / liked-by-me, comment count and
 * the latest 3 comments. `canPost` mirrors the super-admin canSocialPost toggle.
 */
export async function GET(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();

  const before = req.nextUrl.searchParams.get("before");
  const beforeDate = before ? new Date(before) : null;

  const [posts, perms] = await Promise.all([
    db.socialPost.findMany({
      where: {
        companyId: me.companyId,
        ...(beforeDate && !isNaN(beforeDate.getTime()) ? { createdAt: { lt: beforeDate } } : {}),
      },
      orderBy: { createdAt: "desc" },
      take: 30,
      include: {
        author: { include: authorInclude },
        likes: { select: { userId: true } },
        _count: { select: { comments: true } },
        comments: {
          orderBy: { createdAt: "desc" },
          take: 3,
          include: { user: { select: { name: true } } },
        },
      },
    }),
    getPerms(me.employeeId),
  ]);

  const staff = me.role !== "EMPLOYEE";
  return NextResponse.json({
    canPost: perms.canSocialPost,
    posts: posts.map((p) => ({
      id: p.id,
      body: p.body,
      createdAt: p.createdAt,
      at: timeAgo(p.createdAt),
      author: {
        name: p.author.name,
        dept: p.author.employee?.department?.name ?? null,
        photo: p.author.employee?.photoExt ? `/api/photo/${p.author.employee.id}` : null,
      },
      likes: p.likes.length,
      liked: p.likes.some((l) => l.userId === me.id),
      commentCount: p._count.comments,
      comments: p.comments
        .reverse()
        .map((c) => ({ id: c.id, body: c.body, user: c.user.name, at: timeAgo(c.createdAt) })),
      own: p.authorId === me.id,
      canDelete: p.authorId === me.id || staff,
    })),
  });
}

/** POST /api/social {body} — new wall post (canSocialPost-enforced). */
export async function POST(req: NextRequest) {
  const me = await apiUser(req);
  if (!me) return unauthorized();
  const deny = await permDenied(me.employeeId, "canSocialPost");
  if (deny) return jsonError(deny, 403);

  const payload = await req.json().catch(() => null);
  const body = String(payload?.body ?? "").trim();
  if (body.length < 3) return jsonError("Write at least a few words.");
  if (body.length > 1500) return jsonError("Post too long (max 1500 characters).");

  const post = await db.socialPost.create({
    data: { companyId: me.companyId, authorId: me.id, body },
    select: { id: true, createdAt: true },
  });
  return NextResponse.json({ post }, { status: 201 });
}
