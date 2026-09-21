import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/auth";
import { LoginForm } from "./LoginForm";
import { Icon } from "@/components/icons";
import { HLogo } from "@/components/Sidebar";

export const dynamic = "force-dynamic";

function BrandPanel() {
  return (
    <div className="relative hidden w-[45%] flex-col justify-between overflow-hidden bg-[#0a1628] p-10 text-white lg:flex">
      <div className="pointer-events-none absolute -right-20 -top-28 h-80 w-80 rounded-full bg-emerald-500/20 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-28 -left-16 h-72 w-72 rounded-full bg-teal-500/10 blur-3xl" />
      <div className="relative flex items-center gap-3">
        <HLogo className="h-11 w-11" />
        <span className="text-lg font-bold tracking-tight">HRMate</span>
      </div>
      <div className="relative">
        <h2 className="text-3xl font-extrabold leading-tight tracking-tight">
          Factory people, punch<br />&amp; gate pass — <span className="text-emerald-400">sorted.</span>
        </h2>
        <p className="mt-3 max-w-sm text-sm leading-relaxed text-slate-400">
          Your whole workforce in one clean workspace. Biometric-style punches, leave & gate pass approvals, ID cards with QR — no spreadsheets, no WhatsApp chaos.
        </p>
        <ul className="mt-6 space-y-3 text-sm text-slate-300">
          {["Live shift ring timer & weekly-off rules", "Approvals hub: Leave / Punch / OT / Gate Pass", "Yellow Card vs Official staff policies built-in"].map((f) => (
            <li key={f} className="flex items-center gap-2.5">
              <span className="flex h-6 w-6 items-center justify-center rounded-full bg-emerald-500/15 text-emerald-400">
                <Icon name="check" className="h-3.5 w-3.5" />
              </span>
              {f}
            </li>
          ))}
        </ul>
      </div>
      <p className="relative text-xs text-slate-600">© {new Date().getFullYear()} HRMate · Secure JWT sessions Hosted on GCP Mumbai</p>
    </div>
  );
}

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ setup?: string }> }) {
  const user = await getSessionUser();
  if (user) redirect("/dashboard");
  const { setup } = await searchParams;

  return (
    <main className="flex min-h-screen bg-[#0a1628]">
      <BrandPanel />
      <div className="flex flex-1 items-center justify-center bg-[#f6f7f9] px-4">
        <div className="w-full max-w-sm animate-fade-up">
          <div className="mb-6 text-center lg:hidden">
            <div className="mx-auto mb-3">
              <HLogo className="mx-auto h-12 w-12 drop-shadow-[0_6px_16px_rgb(16_185_129_/_35%)]" />
            </div>
            <h1 className="text-lg font-bold text-slate-900">HRMate</h1>
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
