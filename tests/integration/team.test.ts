import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import type { Role } from "@prisma/client";

// Replace only the connection target, NOT Prisma/queries: these tests exercise
// real PostgreSQL, the real service, API handlers and signed Bearer auth.
vi.mock("@/lib/db", async () => {
  const raw = process.env.TEAM_TEST_DATABASE_URL;
  if (!raw) throw new Error("TEAM_TEST_DATABASE_URL is required; use an isolated local PostgreSQL database.");
  const url = new URL(raw);
  if (!["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) || url.pathname !== "/hrms_team_test") {
    throw new Error("Refusing to run DB tests outside localhost/hrms_team_test.");
  }
  const { PrismaClient } = await import("@prisma/client");
  return { db: new PrismaClient({ datasourceUrl: raw }) };
});
// A route handler called directly has no Next.js request cache context. The
// cache boundary alone is stubbed; no database or auth operations are mocked.
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

import { db } from "@/lib/db";
import { signSession } from "@/lib/auth";
import { getTeamSnapshot } from "@/lib/team";
import { GET } from "@/app/api/team/route";
import { PATCH } from "@/app/api/team/weekly-off/route";

const run = randomUUID();
const companyA = `team-a-${run}`;
const companyB = `team-b-${run}`;
const production = `production-${run}`;
const quality = `quality-${run}`;
const foreignDept = `foreign-dept-${run}`;
const ids = Object.fromEntries(["in", "out", "absent", "legacy", "inactive", "foreign"].map((key) => [key, `${key}-${run}`]));
const leaveType = `el-${run}`;
const date = new Date("2026-09-27T00:00:00Z");
const now = new Date("2026-09-27T11:00:00Z");
const tokens = new Map<Role, string>();

beforeAll(async () => {
  vi.stubEnv("AUTH_SECRET", `isolated-team-tests-${randomUUID()}`);
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(now);
  await db.company.createMany({ data: [
    { id: companyA, name: "P2 S2 test company A", code: `TA-${run}` },
    { id: companyB, name: "P2 S2 test company B", code: `TB-${run}` },
  ] });
  await db.department.createMany({ data: [
    { id: production, name: "Production", companyId: companyA },
    { id: quality, name: "Quality", companyId: companyA },
    { id: foreignDept, name: "Private department", companyId: companyB },
  ] });
  const shift = await db.shift.create({ data: { companyId: companyA, name: "General", startTime: "08:00" } });
  await db.employee.createMany({ data: Object.entries(ids).map(([key, id]) => ({
    id, code: key.toUpperCase(), firstName: key, lastName: "Fixture",
    companyId: key === "foreign" ? companyB : companyA,
    departmentId: key === "foreign" ? foreignDept : key === "absent" ? quality : production,
    status: key === "inactive" ? "INACTIVE" : "ACTIVE",
    shiftId: key === "foreign" ? null : shift.id,
    joinDate: date, weeklyOff: 0, baseSalary: 12345, bankAccount: "not-in-team-response",
  })) });
  await db.attendance.createMany({ data: [
    { companyId: companyA, employeeId: ids.in, date, status: "PRESENT", checkIn: new Date("2026-09-27T02:30:00Z") },
    { companyId: companyA, employeeId: ids.out, date, status: "PRESENT", checkIn: new Date("2026-09-27T01:30:00Z"), checkOut: new Date("2026-09-27T10:30:00Z") },
    { companyId: companyA, employeeId: ids.legacy, date, status: "PRESENT" },
    { companyId: companyB, employeeId: ids.foreign, date, status: "PRESENT", checkIn: now },
  ] });
  await db.leaveType.createMany({ data: [
    { id: leaveType, companyId: companyA, name: "Earned Leave" },
    { id: `foreign-${leaveType}`, companyId: companyB, name: "Private leave type" },
  ] });
  const leave = (name: string, from: string, to: string) => ({
    id: `${name}-${run}`, companyId: companyA, employeeId: ids.absent, leaveTypeId: leaveType,
    fromDate: new Date(`${from}T00:00:00Z`), toDate: new Date(`${to}T00:00:00Z`), days: 3,
    status: "APPROVED" as const,
  });
  await db.leaveRequest.createMany({ data: [
    leave("ongoing", "2026-09-25", "2026-09-28"),
    leave("today", "2026-09-27", "2026-09-27"),
    leave("last-day", "2026-10-10", "2026-10-12"),
    leave("ended", "2026-09-25", "2026-09-26"),
    leave("outside", "2026-10-11", "2026-10-12"),
    { ...leave("pending", "2026-09-28", "2026-09-29"), status: "PENDING" },
    { ...leave("rejected", "2026-09-28", "2026-09-29"), status: "REJECTED" },
    { ...leave("foreign-leave", "2026-09-28", "2026-09-29"), companyId: companyB, employeeId: ids.foreign, leaveTypeId: `foreign-${leaveType}` },
  ] });
  for (const role of ["ADMIN", "HR", "EMPLOYEE"] as const) {
    const user = await db.user.create({ data: {
      companyId: companyA, role, name: `${role} Fixture`, email: `${role}-${run}@example.invalid`,
      passwordHash: "not-a-login-credential",
    } });
    tokens.set(role, await signSession({ ...user, companyName: "P2 S2 test company A" }));
  }
});

afterAll(async () => {
  try {
    // Clear requests first because leave-type deletion is restricted. Only
    // this run's fixture companies are touched; remaining relations cascade.
    await db.leaveRequest.deleteMany({ where: { companyId: { in: [companyA, companyB] } } });
    await db.company.deleteMany({ where: { id: { in: [companyA, companyB] } } });
  } finally {
    await db.$disconnect();
    vi.useRealTimers();
    vi.unstubAllEnvs();
  }
});

function request(role: Role, path = "", body?: unknown) {
  return new NextRequest(`https://test.invalid/api/team${path}`, {
    method: body === undefined ? "GET" : "PATCH",
    headers: { Authorization: `Bearer ${tokens.get(role)}`, "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

describe("Live Team with real PostgreSQL", () => {
  it.each(["ADMIN", "HR"] as const)("allows %s, scopes active employees and preserves counts/times", async (role) => {
    const response = await GET(request(role));
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.date).toBe("2026-09-27");
    expect(data.rows.map((r: { id: string }) => r.id).sort()).toEqual([ids.in, ids.out, ids.absent, ids.legacy].sort());
    expect(data.counts).toEqual({ in: 2, out: 1, absent: 1, done: 1 });
    expect(data.rows.find((r: { id: string }) => r.id === ids.in).inAt).toBe("08:00 AM");
    expect(data.rows.find((r: { id: string }) => r.id === ids.out)).toMatchObject({ outAt: "04:00 PM", completed: true });
    expect(data.rows.find((r: { id: string }) => r.id === ids.legacy)).toMatchObject({ status: "IN", inAt: null });
    expect(JSON.stringify(data)).not.toMatch(/not-in-team-response|bankAccount|baseSalary|Private department|Private leave type/);
  });

  it("filters the board, but keeps upcoming leaves company-wide and overlapping", async () => {
    const data = await getTeamSnapshot(companyA, production, now);
    expect(data.rows).toHaveLength(3);
    expect(data.counts).toEqual({ in: 2, out: 1, absent: 0, done: 1 });
    expect(data.leaves.map((l) => l.id)).toEqual([`ongoing-${run}`, `today-${run}`, `last-day-${run}`]);
    expect(data.leaves.every((l) => l.dept === "Quality")).toBe(true);
    expect(data.departments.map((d) => d.id).sort()).toEqual([production, quality].sort());
  });

  it("cannot use a foreign department ID or companyId query to see another tenant", async () => {
    const response = await GET(request("HR", `?dept=${foreignDept}&companyId=${companyB}`));
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.rows).toEqual([]);
    expect(data.counts).toEqual({ in: 0, out: 0, absent: 0, done: 0 });
    expect(data.leaves.map((l: { id: string }) => l.id)).not.toContain(`foreign-leave-${run}`);
  });

  it("denies employee reads and writes even with a valid signed session", async () => {
    expect((await GET(request("EMPLOYEE"))).status).toBe(403);
    expect((await PATCH(request("EMPLOYEE", "/weekly-off", { employeeId: ids.in, weeklyOff: 6 }))).status).toBe(403);
    expect((await db.employee.findUniqueOrThrow({ where: { id: ids.in } })).weeklyOff).toBe(0);
  });

  it("persists all seven weekly-off days, visible in both database and board", async () => {
    for (const day of [1, 2, 3, 4, 5, 6, 0]) {
      const response = await PATCH(request("HR", "/weekly-off", { employeeId: ids.in, weeklyOff: day }));
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ employeeId: ids.in, weeklyOff: day });
      const employee = await db.employee.findUniqueOrThrow({ where: { id: ids.in } });
      expect(employee).toMatchObject({ weeklyOff: day, baseSalary: 12345, bankAccount: "not-in-team-response" });
      const board = await getTeamSnapshot(companyA, "", now);
      expect(board.rows.find((r) => r.id === ids.in)?.weeklyOff).toBe(day);
    }
  });

  it("rejects malformed/cross-tenant updates without changing a row", async () => {
    for (const day of [-1, 7, 2.5, "2", null]) {
      expect((await PATCH(request("ADMIN", "/weekly-off", { employeeId: ids.in, weeklyOff: day }))).status).toBe(400);
    }
    expect((await PATCH(request("ADMIN", "/weekly-off", { employeeId: ids.foreign, weeklyOff: 5 }))).status).toBe(404);
    expect((await PATCH(request("ADMIN", "/weekly-off", { employeeId: `missing-${run}`, weeklyOff: 5 }))).status).toBe(404);
    expect((await db.employee.findUniqueOrThrow({ where: { id: ids.in } })).weeklyOff).toBe(0);
    expect((await db.employee.findUniqueOrThrow({ where: { id: ids.foreign } })).weeklyOff).toBe(0);
  });
});
