import { db } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { bt } from "@/lib/i18n";
import { Tt } from "@/components/LangCtx";
import { timeAgo } from "@/lib/utils";
import { SocialWall } from "@/components/SocialWall";

export const dynamic = "force-dynamic";

export default async function SocialPage() {
  const me = await requireUser();
  const posts = await db.socialPost.findMany({
    where: { companyId: me.companyId },
    orderBy: { createdAt: "desc" },
    take: 50,
    include: { author: true, likes: true, comments: { include: { user: true }, orderBy: { createdAt: "asc" } } },
  });

  const rows = posts.map((p) => ({
    id: p.id,
    body: p.body,
    at: timeAgo(p.createdAt),
    author: p.author.name,
    role: p.author.role,
    photo: null as string | null,
    likes: p.likes.length,
    liked: p.likes.some((l) => l.userId === me.id),
    own: p.authorId === me.id,
    staff: me.role !== "EMPLOYEE",
    comments: p.comments.map((c) => ({ id: c.id, body: c.body, user: c.user.name, at: timeAgo(c.createdAt), photo: null as string | null })),
  }));

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight text-slate-900"><Tt>Social Wall</Tt></h1>
        <p className="text-sm text-slate-500">
          <Tt>Shout-outs, birthday wishes, team moments — visible to everyone at</Tt> {me.companyName}.
        </p>
      </div>
      <SocialWall posts={rows} placeholder={await bt("Share something with the team…")} />
    </div>
  );
}
