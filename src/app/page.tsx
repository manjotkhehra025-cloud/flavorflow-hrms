import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/auth";
import { db } from "@/lib/db";

export const dynamic = "force-dynamic";

export default async function Home() {
  const userCount = await db.user.count();
  if (userCount === 0) redirect("/setup");
  const user = await getSessionUser();
  redirect(user ? "/dashboard" : "/login");
}
