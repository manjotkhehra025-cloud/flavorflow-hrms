import { requireUser } from "@/lib/auth";
import { Sidebar } from "@/components/Sidebar";

export const dynamic = "force-dynamic";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();

  return (
    <div className="flex min-h-screen">
      <div className="sticky top-0 hidden h-screen md:block">
        <Sidebar userName={user.name} role={user.role} companyName={user.companyName} />
      </div>
      {/* Mobile top bar */}
      <div className="fixed inset-x-0 top-0 z-20 flex items-center justify-between bg-slate-950 px-4 py-3 md:hidden">
        <span className="text-sm font-semibold text-white">{user.companyName} HRMS</span>
        <MobileNav role={user.role} />
      </div>
      <main className="flex-1 px-4 pb-16 pt-20 md:px-8 md:pt-8">{children}</main>
    </div>
  );
}

import Link from "next/link";
function MobileNav({ role }: { role: string }) {
  const links = [
    { href: "/dashboard", label: "Home" },
    ...(role !== "EMPLOYEE" ? [{ href: "/employees", label: "Team" }] : []),
    { href: "/attendance", label: "Attendance" },
    { href: "/leaves", label: "Leaves" },
    { href: "/holidays", label: "Holidays" },
  ];
  return (
    <nav className="flex gap-3 text-xs font-medium text-slate-300">
      {links.map((l) => (
        <Link key={l.href} href={l.href} className="hover:text-amber-400">
          {l.label}
        </Link>
      ))}
    </nav>
  );
}
