import { cookies } from "next/headers";
import { SignJWT, jwtVerify } from "jose";
import { redirect } from "next/navigation";

export type SessionUser = {
  id: string;
  companyId: string;
  companyName: string;
  email: string;
  name: string;
  role: "ADMIN" | "HR" | "EMPLOYEE";
  employeeId: string | null;
};

const COOKIE = "ff_session";
const DAYS = 7;

function secretKey() {
  const s = process.env.AUTH_SECRET;
  if (!s) throw new Error("AUTH_SECRET is not set");
  return new TextEncoder().encode(s);
}

export async function signSession(user: SessionUser): Promise<string> {
  return new SignJWT({
    cid: user.companyId,
    companyName: user.companyName,
    email: user.email,
    name: user.name,
    role: user.role,
    employeeId: user.employeeId,
  })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime(`${DAYS}d`)
    .sign(secretKey());
}

export async function setSessionCookie(token: string) {
  const store = await cookies();
  store.set(COOKIE, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    maxAge: DAYS * 24 * 60 * 60,
    path: "/",
  });
}

export async function clearSessionCookie() {
  const store = await cookies();
  store.delete(COOKIE);
}

export async function getSessionUser(): Promise<SessionUser | null> {
  const store = await cookies();
  const token = store.get(COOKIE)?.value;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secretKey());
    return {
      id: payload.sub as string,
      companyId: payload.cid as string,
      companyName: payload.companyName as string,
      email: payload.email as string,
      name: payload.name as string,
      role: payload.role as SessionUser["role"],
      employeeId: (payload.employeeId as string) ?? null,
    };
  } catch {
    return null;
  }
}

/** For server components/actions: redirects to /login when signed out. */
export async function requireUser(): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  return user;
}

/** For admin/HR-only pages. */
export async function requireStaff(): Promise<SessionUser> {
  const user = await requireUser();
  if (user.role === "EMPLOYEE") redirect("/dashboard");
  return user;
}

/** Verify a Bearer token (used by the JSON API — the future Android app). */
export async function getUserFromToken(token: string | undefined): Promise<SessionUser | null> {
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secretKey());
    return {
      id: payload.sub as string,
      companyId: payload.cid as string,
      companyName: payload.companyName as string,
      email: payload.email as string,
      name: payload.name as string,
      role: payload.role as SessionUser["role"],
      employeeId: (payload.employeeId as string) ?? null,
    };
  } catch {
    return null;
  }
}
