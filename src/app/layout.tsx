import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "HRMate — Smart Workforce & Attendance",
  description: "HRMate HRMS for G.D. Foods Mfg. (I) Pvt. Ltd. — people, attendance, leaves, gate passes.",
  icons: { icon: "/favicon.svg" },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-slate-50 text-slate-900 antialiased">{children}</body>
    </html>
  );
}
