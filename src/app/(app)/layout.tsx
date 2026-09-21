import { requireUser } from "@/lib/auth";
import { Sidebar } from "@/components/Sidebar";
import { MobileTopBar, MobileBottomNav } from "@/components/MobileNav";

export const dynamic = "force-dynamic";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();

  return (
    <div className="flex min-h-screen">
      {/* Desktop sidebar */}
      <Sidebar name={user.name} role={user.role} companyName={user.companyName} />

      {/* Mobile chrome (fixed, out of flow) */}
      <MobileTopBar name={user.name} />

      <main className="min-w-0 flex-1 px-4 pb-32 pt-[4.25rem] lg:pl-72 lg:pr-8 lg:pt-8 lg:pb-10">
        <div className="animate-fade-up mx-auto max-w-6xl">{children}</div>
      </main>

      <MobileBottomNav role={user.role} employeeId={user.employeeId} />
    </div>
  );
}
