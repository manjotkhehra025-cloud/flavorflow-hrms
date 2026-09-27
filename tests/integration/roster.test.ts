import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import type { Role } from "@prisma/client";

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
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

import { db } from "@/lib/db";
import { signSession } from "@/lib/auth";
import { getStaffRoster } from "@/lib/roster";
import { GET, PATCH } from "@/app/api/roster/staff/route";

const run = randomUUID();
const companyA = `roster-a-${run}`;
const companyB = `roster-b-${run}`;
const production = `production-${run}`;
const quality = `quality-${run}`;
const foreignDept = `foreign-dept-${run}`;
const ids = Object.fromEntries(["in", "out", "inactive", "foreign"].map((key) => [key, `${key}-${run}`]));
const now = new Date("2026-09-27T11:00:00Z");
const date = new Date("2026-09-27T00:00:00Z");
const tokens = new Map<Role, string>();
let generalId = "";
let nightId = "";

beforeAll(async () => {
  vi.stubEnv("AUTH_SECRET", `isolated-roster-tests-${randomUUID()}`);
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(now);
  await db.company.createMany({ data: [
    { id: companyA, name: "P2 S3 test company A", code: `RA-${run}` },
    { id: companyB, name: "P2 S3 test company B", code: `RB-${run}` },
  ] });
  await db.department.createMany({ data: [
    { id: production, name: "Production", companyId: companyA },
    { id: quality, name: "Quality", companyId: companyA },
    { id: foreignDept, name: "Private department", companyId: companyB },
  ] });
  const general = await db.shift.create({ data: { companyId: companyA, name: "General", startTime: "08:00" } });
  const night = await db.shift.create({ data: { companyId: companyA, name: "Night", startTime: "19:00", durationH: 12 } });
  generalId = general.id;
  nightId = night.id;
  await db.employee.createMany({ data: Object.entries(ids).map(([key, id]) => ({
    id, code: `R-${key}-${run}`.slice(0, 20), firstName: key, lastName: "Fixture",
    companyId: key === "foreign" ? companyB : companyA,
    departmentId: key === "foreign" ? foreignDept : key === "out" ? quality : production,
    status: key === "inactive" ? "INACTIVE" : "ACTIVE",
    shiftId: key === "foreign" ? null : general.id,
    joinDate: date, weeklyOff: 0, baseSalary: 12345, bankAccount: "not-in-roster-response",
  })) });
  await db.shiftAssignment.create({
    data: { companyId: companyA, employeeId: ids.in, date: new Date("2026-09-23T00:00:00Z"), isOff: true },
  });
  await db.shiftSwapRequest.create({
    data: {
      companyId: companyA, requesterId: ids.in, peerId: ids.out,
      date: new Date("2026-09-21T00:00:00Z"), note: "Family function",
    },
  });
  for (const role of ["ADMIN", "HR", "EMPLOYEE"] as const) {
    const user = await db.user.create({ data: {
      companyId: companyA, role, name: `${role} Fixture`, email: `${role}-roster-${run}@example.invalid`,
      passwordHash: "not-a-login-credential", employeeId: role === "EMPLOYEE" ? ids.in : null,
    } });
    tokens.set(role, await signSession({ ...user, companyName: "P2 S3 test company A" }));
  }
});

afterAll(async () => {
  try {
    await db.shiftSwapRequest.deleteMany({ where: { companyId: { in: [companyA, companyB] } } });
    await db.company.deleteMany({ where: { id: { in: [companyA, companyB] } } });
  } finally {
    await db.$disconnect();
    vi.useRealTimers();
    vi.unstubAllEnvs();
  }
});

function request(role: Role, query = "", body?: unknown) {
  return new NextRequest(`https://test.invalid/api/roster/staff${query}`, {
    method: body === undefined ? "GET" : "PATCH",
    headers: { Authorization: `Bearer ${tokens.get(role)}`, "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

describe("staff roster with real PostgreSQL", () => {
  it.each(["ADMIN", "HR"] as const)("allows %s, scopes active employees and keeps Sunday as default", async (role) => {
    const response = await GET(request(role, "?w=2026-09-21"));
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.weekStart).toBe("2026-09-21");
    expect(data.today).toBe("2026-09-27");
    expect(data.employees.map((r: { id: string }) => r.id).sort()).toEqual([ids.in, ids.out].sort());
    const gurpreet = data.employees.find((r: { id: string }) => r.id === ids.in);
    expect(gurpreet.cells["2026-09-23"]).toEqual({ shiftId: "", isOff: true });
    expect(gurpreet.cells["2026-09-27"]).toEqual({ shiftId: "", isOff: false });
    expect(data.pendingSwapCount).toBe(1);
    expect(JSON.stringify(data)).not.toMatch(/not-in-roster-response|bankAccount|baseSalary|Private department/);
  });

  it("cannot use a foreign companyId query to see another tenant", async () => {
    const response = await GET(request("HR", `?w=2026-09-21&companyId=${companyB}`));
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.employees.map((r: { id: string }) => r.id)).not.toContain(ids.foreign);
  });

  it("denies employee reads and writes even with a valid signed session", async () => {
    expect((await GET(request("EMPLOYEE"))).status).toBe(403);
    expect((await PATCH(request("EMPLOYEE", "", {
      entries: [{ employeeId: ids.in, date: "2026-09-22", shiftId: nightId, isOff: false }],
    }))).status).toBe(403);
    const row = await db.shiftAssignment.findFirst({ where: { employeeId: ids.in, date: new Date("2026-09-22T00:00:00Z") } });
    expect(row).toBeNull();
  });

  it("persists override, OFF and restore-to-default against the shared board", async () => {
    const save = await PATCH(request("HR", "", { entries: [
      { employeeId: ids.in, date: "2026-09-22", shiftId: nightId, isOff: false },
      { employeeId: ids.in, date: "2026-09-24", shiftId: null, isOff: true },
    ] }));
    expect(save.status).toBe(200);
    expect(await save.json()).toEqual({ saved: 2 });

    const board = await getStaffRoster(companyA, { week: "2026-09-21", now });
    expect(board.ok).toBe(true);
    if (!board.ok) return;
    const cells = board.employees.find((e) => e.id === ids.in)!.cells;
    expect(cells["2026-09-22"]).toEqual({ shiftId: nightId, isOff: false });
    expect(cells["2026-09-24"]).toEqual({ shiftId: "", isOff: true });

    const restore = await PATCH(request("ADMIN", "", { entries: [
      { employeeId: ids.in, date: "2026-09-22", shiftId: null, isOff: false },
    ] }));
    expect(restore.status).toBe(200);
    expect(await db.shiftAssignment.findFirst({
      where: { employeeId: ids.in, date: new Date("2026-09-22T00:00:00Z") },
    })).toBeNull();
    expect(generalId).toBeTruthy();
  });

  it("rejects malformed/cross-tenant updates without changing a row", async () => {
    const before = await db.shiftAssignment.count({ where: { companyId: companyA } });
    expect((await PATCH(request("ADMIN", "", { entries: [{ employeeId: ids.in, date: "2026-09-40", isOff: false }] }))).status).toBe(400);
    expect((await PATCH(request("ADMIN", "", { entries: [{ employeeId: ids.in, date: "2026-09-22", shiftId: "missing", isOff: false }] }))).status).toBe(400);
    expect((await PATCH(request("ADMIN", "", { entries: [{ employeeId: ids.foreign, date: "2026-09-22", isOff: true }] }))).status).toBe(404);
    expect(await db.shiftAssignment.count({ where: { companyId: companyA } })).toBe(before);
  });
});
