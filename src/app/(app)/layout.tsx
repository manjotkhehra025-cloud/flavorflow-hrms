import { requireUser } from "@/lib/auth";
import { getRequestLang } from "@/lib/i18n";
import { LangProvider } from "@/components/LangCtx";
import { Sidebar } from "@/components/Sidebar";
import { MobileTopBar, MobileBottomNav } from "@/components/MobileNav";
import { AlertsBell, type AlertUi } from "@/components/AlertsBell";
import { getAlerts } from "@/lib/alerts";

export const dynamic = "force-dynamic";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const lang = await getRequestLang();
  const alerts = await getAlerts({ companyId: user.companyId, role: user.role, employeeId: user.employeeId });
  const alertItems: AlertUi[] = alerts.items.map((a) => ({ ...a, kind: a.kind as AlertUi["kind"], at: a.at ? a.at.toISOString() : null }));

  return (
    <LangProvider lang={lang}>
    <div className="flex min-h-screen">
      {/* Desktop sidebar */}
      <Sidebar name={user.name} role={user.role} companyName={user.companyName} />

      {/* Mobile chrome (fixed, out of flow) */}
      <MobileTopBar name={user.name} right={<AlertsBell dark count={alerts.count} items={alertItems} />} />

      <div className="fixed right-8 top-6 z-40 hidden lg:block">
        <AlertsBell count={alerts.count} items={alertItems} />
      </div>

      <main className="min-w-0 flex-1 px-4 pb-32 pt-[4.25rem] lg:pl-72 lg:pr-8 lg:pt-8 lg:pb-10">
        <div className="animate-fade-up mx-auto max-w-6xl">{children}</div>
      </main>

      <MobileBottomNav role={user.role} employeeId={user.employeeId} />
    </div>
    </LangProvider>
  );
}
