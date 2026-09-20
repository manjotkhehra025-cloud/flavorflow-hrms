import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/auth";
import { LoginForm } from "./LoginForm";

export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ setup?: string }>;
}) {
  const user = await getSessionUser();
  if (user) redirect("/dashboard");
  const { setup } = await searchParams;

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500 text-xl font-black text-slate-950">
            FF
          </div>
          <h1 className="text-xl font-semibold text-white">FlavorFlow HRMS</h1>
          <p className="mt-1 text-sm text-slate-400">Sign in to your workspace</p>
        </div>
        <div className="rounded-2xl bg-white p-6 shadow-xl">
          {setup === "done" && (
            <p className="mb-4 rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
              Setup complete — sign in with your admin account.
            </p>
          )}
          <LoginForm />
        </div>
      </div>
    </main>
  );
}
