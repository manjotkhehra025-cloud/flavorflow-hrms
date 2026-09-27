import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import { SignJWT } from "jose";
import { cookies } from "next/headers";
import { apiUser } from "@/lib/api-auth";
import { signSession, type SessionUser } from "@/lib/auth";
import { middleware } from "../middleware";

vi.mock("next/headers", () => ({ cookies: vi.fn() }));
const user: SessionUser = {
  id: "admin", companyId: "company-a", companyName: "Test company",
  name: "Test Admin", email: "test@example.invalid", role: "ADMIN", employeeId: null,
};
let cookieToken: string | undefined;
beforeEach(() => {
  vi.stubEnv("AUTH_SECRET", "team-tests-only-not-a-deployment-secret");
  cookieToken = undefined;
  vi.mocked(cookies).mockImplementation(async () => ({
    get: () => cookieToken ? { name: "ff_session", value: cookieToken } : undefined,
  }) as unknown as Awaited<ReturnType<typeof cookies>>);
});

afterEach(() => vi.unstubAllEnvs());

describe("the shared Bearer/cookie auth used by Live Team", () => {
  it("accepts a valid mobile Bearer token through middleware and apiUser", async () => {
    const token = await signSession(user);
    const req = new NextRequest("https://hr.example/api/team", { headers: { Authorization: `Bearer ${token}` } });
    expect((await middleware(req)).headers.get("x-middleware-next")).toBe("1");
    expect(await apiUser(req)).toEqual(user);
    expect(cookies).not.toHaveBeenCalled();
  });

  it("also accepts the web cookie", async () => {
    cookieToken = await signSession(user);
    const req = new NextRequest("https://hr.example/api/team", { headers: { Cookie: `ff_session=${cookieToken}` } });
    expect((await middleware(req)).headers.get("x-middleware-next")).toBe("1");
    expect(await apiUser(req)).toEqual(user);
  });

  it.each([undefined, "not-a-jwt"])("rejects missing/invalid mobile authentication (%s)", async (token) => {
    const req = new NextRequest("https://hr.example/api/team", { headers: token ? { Authorization: `Bearer ${token}` } : {} });
    expect((await middleware(req)).status).toBe(401);
    expect(await apiUser(req)).toBeNull();
  });

  it("rejects an expired token", async () => {
    const token = await new SignJWT({ cid: user.companyId, role: "ADMIN" })
      .setProtectedHeader({ alg: "HS256" }).setSubject(user.id).setExpirationTime(0)
      .sign(new TextEncoder().encode(process.env.AUTH_SECRET));
    const req = new NextRequest("https://hr.example/api/team", { headers: { Authorization: `Bearer ${token}` } });
    expect((await middleware(req)).status).toBe(401);
    expect(await apiUser(req)).toBeNull();
  });
});
