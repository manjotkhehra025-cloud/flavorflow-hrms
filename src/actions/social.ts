"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import type { ActionState } from "./auth";

export async function createPostAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const body = String(formData.get("body") ?? "").trim();
  if (body.length < 3) return { error: await bt("Write at least a few words.") };
  if (body.length > 1500) return { error: await bt("Post too long (max 1500 characters).") };
  await db.socialPost.create({ data: { companyId: me.companyId, authorId: me.id, body } });
  revalidatePath("/social");
  return { success: await bt("Posted to the wall") };
}

export async function toggleLikeAction(postId: string) {
  const me = await requireUser();
  const existing = await db.postLike.findUnique({ where: { postId_userId: { postId, userId: me.id } } });
  if (existing) await db.postLike.delete({ where: { id: existing.id } });
  else {
    const post = await db.socialPost.findFirst({ where: { id: postId, companyId: me.companyId } });
    if (!post) return;
    await db.postLike.create({ data: { postId, userId: me.id } });
  }
  revalidatePath("/social");
}

export async function commentAction(postId: string, formData: FormData): Promise<ActionState> {
  const me = await requireUser();
  const body = String(formData.get("body") ?? "").trim();
  if (!body) return { error: await bt("Empty comment.") };
  if (body.length > 400) return { error: await bt("Comment too long.") };
  await db.postComment.create({ data: { postId, userId: me.id, body } });
  revalidatePath("/social");
  return { success: await bt("Comment added") };
}

export async function deletePostAction(id: string) {
  const me = await requireUser();
  const post = await db.socialPost.findFirst({ where: { id, companyId: me.companyId } });
  if (!post) return;
  if (post.authorId !== me.id && me.role === "EMPLOYEE") return;
  await db.socialPost.delete({ where: { id } });
  revalidatePath("/social");
}
