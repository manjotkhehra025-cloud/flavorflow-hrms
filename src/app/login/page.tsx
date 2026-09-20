import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/auth";
import { LoginForm } from "./LoginForm";
import { Icon } from "@/components/icons";

export const dynamic = "force-dynamic";

function BrandPanel() {
  return (
    <div className="relative hidden w-[45%] flex-col justify-between overflow-hidden bg-slate-950 p-10 text-white lg:flex">
      <div className="pointer-events-none absolute -right-20 -top-28 h-80 w-80 rounded-full bg-amber-500/25 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-28 -left-16 h-72 w-72 rounded-full bg-amber-500/10 blur-3xl" />
      <div className="relative flex items-center gap-3">
        <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-amber-400 to-amber-600 text-base font-black text-slate-950 shadow-[0_4px_16px_-2px_rgb(245_158_11_/_50%)]">
          FF
        </div>
        <span className="text-lg font-bold">FlavorFlow HRMS</span>
      </div>
      <div className="relative">
        <h2 className="text-3xl font-extrabold leading-tight tracking-tight">
          People, attendance<br />&amp; leave — <span className="text-amber-400">sorted.</span>
        </h2>
        <p className="mt-3 max-w-sm text-sm leading-relaxed text-slate-400">
          Your whole team in one clean workspace. Check-ins, leave approvals and holidays — no spreadsheets, no WhatsApp chaos.
        </p>
        <ul className="mt-6 space-y-3 text-sm text-slate-300">
          {["One-tap attendance check-ins", "Leave requests & approvals in seconds", "Roles: Admin, HR and Employee"].map((f) => (
            <li key={f} className="flex items-center gap-2.5">
              <span className="flex h-6 w-6 items-center justify-center rounded-full bg-amber-500/15 text-amber-400">
                <Icon name="check" className="h-3.5 w-3.5" />
              </span>
              {f}
            </li>
          ))}
        </ul>
      </div>
      <p className="relative text-xs text-slate-600">© {new Date().getFullYear()} · Secure JWT sessions · Hosted on GCP Mumbai</p>
    </div>
  );
}

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ setup?: string }> }) {
  const user = await getSessionUser();
  if (user) redirect("/dashboard");
  const { setup } = await searchParams;

  return (
    <main className="flex min-h-screen bg-slate-950">
      <BrandPanel />
      <div className="flex flex-1 items-center justify-center bg-[#f6f7f9] px-4">
        <div className="w-full max-w-sm animate-fade-up">
          <div className="mb-6 text-center lg:hidden">
            <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-slate-950 text-xl font-black text-amber-400">
              FF
            </div>
            <h1 className="text-lg font-bold text-slate-900">FlavorFlow HRMS</h1>
          </div>
          <div className="card p-7">
            <h2 className="text-lg font-bold text-slate-900">Welcome back</h2>
            <p className="mb-5 mt-0.5 text-sm text-slate-500">Sign in to your workspace</p>
            {setup === "done" && (
              <p className="mb-4 rounded-xl bg-emerald-50 px-3.5 py-2.5 text-sm font-medium text-emerald-700 ring-1 ring-inset ring-emerald-600/20">
                Setup complete — sign in with your admin account.
              </p>
            )}
            <LoginForm />
          </div>
        </div>
      </div>
    </main>
  );
}
