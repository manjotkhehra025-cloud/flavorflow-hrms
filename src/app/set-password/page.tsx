import { Pa } from "@/components/Pa";
import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/auth";
import { db } from "@/lib/db";
import { HLogo } from "@/components/Sidebar";
import { LangProvider } from "@/components/LangCtx";
import { LangToggle } from "@/components/LangToggle";
import { getRequestLang } from "@/lib/i18n";
import { SetPasswordForm } from "./SetPasswordForm";

export const dynamic = "force-dynamic";

export default async function SetPasswordPage() {
  const me = await getSessionUser();
  if (!me) redirect("/login");
  // Already picked their own password → straight into the app.
  const fresh = await db.user.findUnique({ where: { id: me.id }, select: { mustChangePassword: true } });
  if (!fresh?.mustChangePassword) redirect("/dashboard");
  const lang = await getRequestLang();

  return (
    <LangProvider lang={lang}>
      <div className="flex min-h-screen items-center justify-center bg-[#0a1628] px-4">
        <div className="pointer-events-none fixed -right-24 -top-24 h-96 w-96 rounded-full bg-emerald-500/15 blur-3xl" />
        <div className="pointer-events-none fixed -bottom-24 -left-24 h-80 w-80 rounded-full bg-teal-500/10 blur-3xl" />

        <div className="relative w-full max-w-sm">
          <div className="mb-8 flex flex-col items-center text-center">
            <HLogo className="h-14 w-14" />
            <h1 className="mt-3 font-display text-2xl font-black tracking-tight text-white">
              <Pa>Choose your own password</Pa>
            </h1>
            <p className="mt-1 text-sm text-slate-400">
              <Pa>Hi</Pa> {me.name} — <Pa>this keeps your account yours alone.</Pa>
            </p>
          </div>

          <div className="rounded-3xl bg-white/[0.03] p-6 ring-1 ring-white/10 backdrop-blur">
            <SetPasswordForm />
          </div>

          <div className="mt-6 flex justify-center">
            <LangToggle dark />
          </div>
        </div>
      </div>
    </LangProvider>
  );
}
