import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

/**
 * Public without a session. `/share` is the token-gated payslip link (WhatsApp,
 * no login). `/download` + `/native` are the internal APK. Static brand files
 * (logo on the login page) must not bounce to /login.
 */
const PUBLIC_PREFIXES = ["/login", "/setup", "/verify", "/share", "/download", "/native", "/api/auth/login", "/api/auth/logout"];

const PUBLIC_FILE = /\.(?:png|svg|jpg|jpeg|gif|webp|ico|apk|txt|xml|webmanifest)$/i;

function isPublic(pathname: string) {
  if (PUBLIC_PREFIXES.some((p) => pathname === p || pathname.startsWith(p + "/"))) return true;
  if (pathname.startsWith("/_next") || pathname.startsWith("/favicon")) return true;
  if (PUBLIC_FILE.test(pathname)) return true;
  return false;
}

/**
 * Web sends the httpOnly cookie. The Flutter app sends only
 * `Authorization: Bearer <jwt>`. Both are the same signed session — middleware
 * used to ignore the header, so every mobile call died with 401 before the
 * route handler could see the token.
 */
function sessionToken(req: NextRequest): string | undefined {
  const header = req.headers.get("authorization");
  if (header) {
    const match = /^Bearer\s+(\S+)/i.exec(header);
    if (match?.[1]) return match[1];
  }
  return req.cookies.get("ff_session")?.value;
}

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  if (isPublic(pathname)) return NextResponse.next();

  const token = sessionToken(req);
  let valid = false;
  if (token && process.env.AUTH_SECRET) {
    try {
      await jwtVerify(token, new TextEncoder().encode(process.env.AUTH_SECRET));
      valid = true;
    } catch {
      valid = false;
    }
  }

  if (!valid) {
    if (pathname.startsWith("/api/")) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    const url = req.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
