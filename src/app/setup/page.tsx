import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { SetupForm } from "./SetupForm";

export const dynamic = "force-dynamic";

export default async function SetupPage() {
  const userCount = await db.user.count();
  if (userCount > 0) redirect("/login");

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500 text-xl font-black text-slate-950">
            FF
          </div>
          <h1 className="text-xl font-semibold text-white">Welcome — first-time setup</h1>
          <p className="mt-1 text-sm text-slate-400">
            Create your company workspace and admin account. This runs only once.
          </p>
        </div>
        <div className="rounded-2xl bg-white p-6 shadow-xl">
          <SetupForm />
        </div>
      </div>
    </main>
  );
}
