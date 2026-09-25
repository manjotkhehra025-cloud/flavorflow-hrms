import { NextRequest, NextResponse } from "next/server";
import { getSessionUser, getUserFromToken, type SessionUser } from "@/lib/auth";

/** JSON API auth: Bearer token (Flutter app) first, then the web session cookie. */
export async function apiUser(req: NextRequest): Promise<SessionUser | null> {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return (await getUserFromToken(bearer)) ?? (await getSessionUser());
}

export const unauthorized = () => NextResponse.json({ error: "Unauthorized" }, { status: 401 });
export const jsonError = (error: string, status = 400) => NextResponse.json({ error }, { status });
