import { requireUser } from "@/lib/auth";
import { Sidebar } from "@/components/Sidebar";
import { MobileTopBar, MobileBottomNav } from "@/components/MobileNav";

export const dynamic = "force-dynamic";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();

  return (
    <div className="flex min-h-screen">
      {/* Desktop sidebar */}
      <div className="sticky top-0 hidden h-screen md:block">
        <Sidebar userName={user.name} role={user.role} companyName={user.companyName} />
      </div>

      {/* Mobile chrome */}
      <MobileTopBar companyName={user.companyName} userName={user.name} />
      <MobileBottomNav role={user.role} />

      <main className="min-w-0 flex-1 px-4 pb-28 pt-[4.25rem] md:px-8 md:pb-10 md:pt-8">
        <div className="animate-fade-up mx-auto max-w-6xl">{children}</div>
      </main>
    </div>
  );
}
