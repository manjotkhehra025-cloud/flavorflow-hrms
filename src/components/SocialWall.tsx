"use client";

import { useActionState, useRef, useState, useTransition } from "react";
import { AvatarImg } from "./AvatarImg";
import { Tt } from "@/components/LangCtx";
import { createPostAction, toggleLikeAction, commentAction, deletePostAction } from "@/actions/social";
import { cx } from "@/lib/utils";

type Comment = { id: string; body: string; user: string; at: string; photo: string | null };
type Post = { id: string; body: string; at: string; author: string; role: string; photo: string | null; likes: number; liked: boolean; own: boolean; staff: boolean; comments: Comment[] };

export function SocialWall({ posts, placeholder }: { posts: Post[]; placeholder: string }) {
  const [state, formAction, pending] = useActionState(createPostAction, {});
  const formRef = useRef<HTMLFormElement>(null);

  return (
    <div className="space-y-4">
      {/* Composer */}
      <form
        ref={formRef}
        action={async (fd) => { await formAction(fd); formRef.current?.reset(); }}
        className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"
      >
        <textarea
          name="body"
          required
          maxLength={1500}
          rows={2}
          placeholder={placeholder}
          className="w-full resize-none rounded-xl bg-slate-50 px-3.5 py-2.5 text-sm outline-none ring-1 ring-inset ring-slate-200 focus:ring-2 focus:ring-emerald-400"
        />
        <div className="mt-2 flex items-center justify-between">
          <span className="text-xs font-semibold aria-live">{state?.error ? <span className="text-rose-600">{state.error}</span> : <span className="text-emerald-600">{state?.success}</span>}</span>
          <button disabled={pending} className="rounded-xl bg-[#0a1628] px-4 py-2 text-xs font-extrabold text-emerald-300 shadow transition hover:brightness-110 disabled:opacity-50">
            {pending ? "…" : <Tt>Post 🚀</Tt>}
          </button>
        </div>
      </form>

      {posts.length === 0 && (
        <div className="rounded-2xl border border-dashed border-slate-300 bg-white/60 py-12 text-center">
          <p className="text-3xl">📣</p>
          <p className="mt-1 text-sm font-semibold text-slate-500"><Tt>No posts yet — be the first!</Tt></p>
        </div>
      )}

      {posts.map((p) => <PostCard key={p.id} post={p} />)}
    </div>
  );
}

function PostCard({ post }: { post: Post }) {
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();
  const [cState, cAction, cPending] = useActionState(
    async (_prev: any, fd: FormData) => commentAction(post.id, fd), {}
  );
  const cRef = useRef<HTMLFormElement>(null);

  return (
    <article className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
      <div className="flex items-start gap-3 p-4">
        <AvatarImg name={post.author} photoUrl={post.photo} size="h-10 w-10" />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="truncate text-sm font-extrabold text-slate-800">{post.author}</span>
            {post.role !== "EMPLOYEE" && <span className="rounded bg-[#0a1628] px-1.5 py-0.5 text-[9px] font-extrabold tracking-wide text-emerald-300">{post.role}</span>}
            <span className="ml-auto shrink-0 text-[11px] font-semibold text-slate-400">{post.at}</span>
          </div>
          <p className="mt-1 whitespace-pre-wrap text-sm leading-relaxed text-slate-700">{post.body}</p>
        </div>
        {(post.own || post.staff) && (
          <button
            type="button"
            aria-label="Delete"
            onClick={() => startTransition(async () => { await deletePostAction(post.id); })}
            className="shrink-0 rounded-lg p-1.5 text-slate-300 transition hover:bg-rose-50 hover:text-rose-500"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-4 w-4"><path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2m2 0v14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V6" strokeLinecap="round" /></svg>
          </button>
        )}
      </div>

      <div className="flex items-center gap-1 border-t border-slate-100 px-2 py-1.5">
        <button
          type="button"
          disabled={pending}
          onClick={() => startTransition(async () => { await toggleLikeAction(post.id); })}
          className={cx(
            "flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition",
            post.liked ? "bg-emerald-50 text-emerald-600" : "text-slate-500 hover:bg-slate-50"
          )}
        >
          <span className={cx("text-sm", post.liked && "scale-110")}>{post.liked ? "💚" : "🤍"}</span> {post.likes > 0 && post.likes} <Tt>Like</Tt>
        </button>
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold text-slate-500 transition hover:bg-slate-50"
        >
          💬 {post.comments.length > 0 && post.comments.length} <Tt>Comments</Tt>
        </button>
      </div>

      {open && (
        <div className="border-t border-slate-100 bg-slate-50/60 px-4 py-3">
          <div className="space-y-3">
            {post.comments.map((c) => (
              <div key={c.id} className="flex items-start gap-2.5">
                <AvatarImg name={c.user} photoUrl={c.photo} size="h-7 w-7" textSize="text-[10px]" />
                <div className="min-w-0 flex-1 rounded-xl rounded-tl-sm bg-white px-3 py-1.5 ring-1 ring-slate-200">
                  <div className="flex items-baseline gap-2">
                    <span className="text-xs font-extrabold text-slate-700">{c.user}</span>
                    <span className="text-[10px] text-slate-400">{c.at}</span>
                  </div>
                  <p className="text-[13px] text-slate-600">{c.body}</p>
                </div>
              </div>
            ))}
            {post.comments.length === 0 && <p className="text-xs text-slate-400"><Tt>No comments yet.</Tt></p>}
          </div>
          <form ref={cRef} action={async (fd) => { await cAction(fd); cRef.current?.reset(); }} className="mt-3 flex items-center gap-2">
            <input
              name="body"
              required
              maxLength={400}
              placeholder="Add a comment…"
              className="min-w-0 flex-1 rounded-full bg-white px-3.5 py-2 text-xs outline-none ring-1 ring-inset ring-slate-200 focus:ring-2 focus:ring-emerald-400"
            />
            <button disabled={cPending} className="rounded-full bg-emerald-500 px-3.5 py-2 text-xs font-extrabold text-white shadow disabled:opacity-50"><Tt>Send</Tt></button>
          </form>
        </div>
      )}
    </article>
  );
}
