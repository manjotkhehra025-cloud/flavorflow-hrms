import { Pa } from "@/components/Pa";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { SetupForm } from "./SetupForm";

export const dynamic = "force-dynamic";

export default async function SetupPage() {
  const userCount = await db.user.count();
  if (userCount > 0) redirect("/login");

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#0a1628] px-4 py-10">
      <div className="pointer-events-none fixed -right-24 -top-32 h-96 w-96 rounded-full bg-emerald-500/20 blur-3xl" />
      <div className="w-full max-w-md animate-fade-up">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-400 to-emerald-600 text-2xl font-black text-[#0a1628] shadow-[0_8px_24px_-4px_rgb(16_185_129_/_55%)]">{<Pa>H</Pa>}</div>
          <h1 className="text-2xl font-extrabold tracking-tight text-white">{<Pa>Let&apos;s set up your workspace</Pa>}</h1>
          <p className="mt-1.5 text-sm text-slate-400">
            One-time setup — company + admin account.
          </p>
        </div>
        <div className="card p-7">
          <SetupForm />
        </div>
      </div>
    </main>
  );
}
