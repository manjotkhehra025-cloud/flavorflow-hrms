import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  db: {
    employee: { findMany: vi.fn(), updateMany: vi.fn() },
    department: { findMany: vi.fn() },
    attendance: { findMany: vi.fn() },
    leaveRequest: { findMany: vi.fn() },
  },
  user: vi.fn(),
  revalidate: vi.fn(),
}));
vi.mock("@/lib/db", () => ({ db: mocks.db }));
vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidate }));
vi.mock("@/lib/api-auth", async (original) => ({
  ...await original<typeof import("@/lib/api-auth")>(), apiUser: mocks.user,
}));

import { getTeamSnapshot, teamCounts, teamDate, teamPresence, updateTeamWeeklyOff } from "@/lib/team";
import { GET } from "@/app/api/team/route";
import { PATCH } from "@/app/api/team/weekly-off/route";

const now = new Date("2026-09-27T11:00:00Z");
const stamp = (day: string) => new Date(`${day}T00:00:00Z`);
const staff = { id: "admin-1", companyId: "company-a", role: "ADMIN", employeeId: null };
const employee = (id: string, overrides = {}) => ({
  id, companyId: "company-a", status: "ACTIVE", departmentId: "production",
  firstName: id, lastName: "Singh", weeklyOff: 0,
  photoUrl: null, photoExt: null,
  department: { name: "Production" }, shift: { name: "General", startTime: "08:00" },
  baseSalary: 999999, bankAccount: "must-not-be-exposed", ...overrides,
});
let employees: ReturnType<typeof employee>[];

const readRequest = (query = "") => new NextRequest(`https://hr.example/api/team${query}`);
const writeRequest = (body: unknown) => new NextRequest("https://hr.example/api/team/weekly-off", {
  method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
});

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(now);
  vi.clearAllMocks();
  mocks.user.mockResolvedValue(staff);
  employees = [
    employee("in", { photoExt: "jpg" }),
    employee("out"),
    employee("absent", { departmentId: "quality", department: { name: "Quality" }, shift: null }),
    employee("legacy"),
    employee("inactive", { status: "INACTIVE" }),
    employee("foreign", { companyId: "company-b", departmentId: "foreign-dept" }),
  ];
  mocks.db.employee.findMany.mockImplementation(async ({ where }) => employees.filter((e) =>
    e.companyId === where.companyId && e.status === where.status &&
    (!where.departmentId || e.departmentId === where.departmentId),
  ));
  mocks.db.employee.updateMany.mockImplementation(async ({ where, data }) => {
    const e = employees.find((r) => r.id === where.id && r.companyId === where.companyId);
    if (!e) return { count: 0 };
    Object.assign(e, data);
    return { count: 1 };
  });
  mocks.db.department.findMany.mockResolvedValue([
    { id: "production", name: "Production" }, { id: "quality", name: "Quality" },
  ]);
  mocks.db.attendance.findMany.mockResolvedValue([
    { employeeId: "in", status: "PRESENT", checkIn: new Date("2026-09-27T02:30:00Z"), checkOut: null },
    { employeeId: "out", status: "PRESENT", checkIn: new Date("2026-09-27T01:30:00Z"), checkOut: new Date("2026-09-27T10:30:00Z") },
    { employeeId: "legacy", status: "PRESENT", checkIn: null, checkOut: null },
  ]);
  mocks.db.leaveRequest.findMany.mockResolvedValue([]);
});
afterEach(() => vi.useRealTimers());

describe("shared presence/date rules", () => {
  it.each([
    [null, "ABSENT", false],
    [{ status: "ABSENT", checkIn: null, checkOut: null }, "ABSENT", false],
    [{ status: "LEAVE", checkIn: null, checkOut: null }, "ABSENT", false],
    [{ status: "PRESENT", checkIn: null, checkOut: null }, "IN", false],
    [{ status: "HALF_DAY", checkIn: now, checkOut: null }, "IN", false],
    [{ status: "PRESENT", checkIn: now, checkOut: now }, "OUT", true],
    [{ status: "PRESENT", checkIn: null, checkOut: now }, "OUT", true],
    [{ status: "ABSENT", checkIn: null, checkOut: now }, "ABSENT", false],
  ])("maps %j to %s without changing attendance", (att, status, completed) => {
    expect(teamPresence(att)).toEqual({ status, completed });
  });

  it("uses plant midnight, not UTC or the phone's timezone", () => {
    expect(teamDate(new Date("2026-09-26T18:29:59Z"))).toEqual(stamp("2026-09-26"));
    expect(teamDate(new Date("2026-09-26T18:30:00Z"))).toEqual(stamp("2026-09-27"));
    expect(teamDate(new Date("2026-12-31T18:30:00Z"))).toEqual(stamp("2027-01-01"));
  });

  it("keeps Done as a subset of Out, not a fourth attendance bucket", () => {
    expect(teamCounts([
      { status: "IN", completed: false }, { status: "OUT", completed: true },
      { status: "ABSENT", completed: false },
    ])).toEqual({ in: 1, out: 1, absent: 1, done: 1 });
    expect(teamCounts([])).toEqual({ in: 0, out: 0, absent: 0, done: 0 });
  });
});

describe("snapshot query and wire contract", () => {
  it("returns only active employees in the company, correct counts, times and photos", async () => {
    const data = await getTeamSnapshot("company-a", "", now);
    expect(data.date).toBe("2026-09-27");
    expect(data.asOf).toBe(now.toISOString());
    expect(data.timeZone).toBe("Asia/Kolkata");
    expect(data.rows.map((e) => e.id)).toEqual(["in", "out", "absent", "legacy"]);
    expect(data.counts).toEqual({ in: 2, out: 1, absent: 1, done: 1 });
    expect(data.rows[0]).toMatchObject({ inAt: "08:00 AM", outAt: null, photo: "/api/photo/in", weeklyOff: 0 });
    expect(data.rows[1]).toMatchObject({ inAt: "07:00 AM", outAt: "04:00 PM", completed: true });
    expect(data.rows[2].shift).toBe("—");
    expect(data.rows[3]).toMatchObject({ status: "IN", inAt: null });
    expect(JSON.stringify(data)).not.toMatch(/bankAccount|baseSalary|must-not-be-exposed/);
    expect(mocks.db.attendance.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { companyId: "company-a", date: stamp("2026-09-27") } }));
    expect(mocks.db.department.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { companyId: "company-a" } }));
  });

  it("filters both the board and its counters without limiting the department choices", async () => {
    const data = await getTeamSnapshot("company-a", "quality", now);
    expect(data.activeDept).toBe("quality");
    expect(data.rows.map((e) => e.id)).toEqual(["absent"]);
    expect(data.counts).toEqual({ in: 0, out: 0, absent: 1, done: 0 });
    expect(data.departments).toHaveLength(2);
  });

  it("never reveals another company's employees via a department ID", async () => {
    const data = await getTeamSnapshot("company-a", "foreign-dept", now);
    expect(data.rows).toEqual([]);
    expect(data.counts).toEqual({ in: 0, out: 0, absent: 0, done: 0 });
  });

  it("uses an overlapping, approved, company-wide 14-day leave window", async () => {
    const makeLeave = (id: string, from: string, to: string, overrides = {}) => ({
      id, fromDate: stamp(from), toDate: stamp(to), days: 3, status: "APPROVED", companyId: "company-a",
      employee: { companyId: "company-a", firstName: "Simran", lastName: "Kaur", department: { name: "Quality" } },
      leaveType: { name: "Earned Leave" }, ...overrides,
    });
    const leaves = [
      makeLeave("ended", "2026-09-25", "2026-09-26"),
      makeLeave("ongoing", "2026-09-25", "2026-09-28"),
      makeLeave("ends-today", "2026-09-27", "2026-09-27"),
      makeLeave("last-day", "2026-10-10", "2026-10-12"),
      makeLeave("outside", "2026-10-11", "2026-10-12"),
      makeLeave("pending", "2026-09-27", "2026-09-28", { status: "PENDING" }),
      makeLeave("foreign", "2026-09-27", "2026-09-28", { companyId: "company-b" }),
    ];
    mocks.db.leaveRequest.findMany.mockImplementation(async ({ where }) => leaves.filter((l) =>
      l.companyId === where.companyId && l.employee.companyId === where.employee.companyId &&
      l.status === where.status && l.toDate >= where.toDate.gte && l.fromDate < where.fromDate.lt,
    ));
    const data = await getTeamSnapshot("company-a", "production", now);
    expect(data.leaves.map((l) => l.id)).toEqual(["ongoing", "ends-today", "last-day"]);
    expect(data.leaves[0]).toMatchObject({ fromDate: "2026-09-25", toDate: "2026-09-28", days: 3, dept: "Quality" });
    expect(mocks.db.leaveRequest.findMany.mock.calls[0][0].where).not.toHaveProperty("departmentId");
    expect(mocks.db.leaveRequest.findMany.mock.calls[0][0].where.employee).toEqual({ companyId: "company-a" });
  });
});

describe("weekly-off validation and persistence", () => {
  it.each([0, 1, 2, 3, 4, 5, 6])("persists day %s and no other fields", async (day) => {
    const before = { ...employees[0] };
    expect(await updateTeamWeeklyOff("company-a", { employeeId: "in", weeklyOff: day }))
      .toEqual({ ok: true, employeeId: "in", weeklyOff: day });
    expect(employees[0]).toEqual({ ...before, weeklyOff: day });
    expect(mocks.db.employee.updateMany).toHaveBeenCalledWith({ where: { id: "in", companyId: "company-a" }, data: { weeklyOff: day } });
  });

  it.each([-1, 7, 1.5, "1", "", null, true, NaN, Infinity, undefined])("rejects invalid day %s without a write", async (day) => {
    expect(await updateTeamWeeklyOff("company-a", { employeeId: "in", weeklyOff: day })).toMatchObject({ ok: false, status: 400 });
    expect(mocks.db.employee.updateMany).not.toHaveBeenCalled();
  });

  it.each([null, [], {}, { employeeId: "", weeklyOff: 0 }, { employeeId: "in", weeklyOff: 0, companyId: "company-b" }])("rejects malformed input %j", async (body) => {
    expect(await updateTeamWeeklyOff("company-a", body)).toMatchObject({ ok: false, status: 400 });
    expect(mocks.db.employee.updateMany).not.toHaveBeenCalled();
  });

  it.each(["foreign", "missing"])('returns the same 404 for "%s", without mutating it', async (id) => {
    expect(await updateTeamWeeklyOff("company-a", { employeeId: id, weeklyOff: 4 })).toEqual({ ok: false, status: 404, error: "Employee not found." });
    expect(employees.find((e) => e.id === "foreign")?.weeklyOff).toBe(0);
  });
});

describe("Live Team HTTP handlers", () => {
  it.each([null, { ...staff, role: "EMPLOYEE" }])("gates both endpoints before any data access (%j)", async (user) => {
    mocks.user.mockResolvedValue(user);
    const expected = user ? 403 : 401;
    expect((await GET(readRequest())).status).toBe(expected);
    expect((await PATCH(writeRequest({ employeeId: "in", weeklyOff: 2 }))).status).toBe(expected);
    expect(mocks.db.employee.findMany).not.toHaveBeenCalled();
    expect(mocks.db.employee.updateMany).not.toHaveBeenCalled();
  });

  it.each(["ADMIN", "HR"])("allows %s to read and update; invalidates the web views", async (role) => {
    mocks.user.mockResolvedValue({ ...staff, role });
    const response = await GET(readRequest("?dept=quality&companyId=company-b"));
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect((await response.json()).rows.map((r: { id: string }) => r.id)).toEqual(["absent"]);
    const saved = await PATCH(writeRequest({ employeeId: "in", weeklyOff: 5 }));
    expect(saved.status).toBe(200);
    expect(await saved.json()).toEqual({ employeeId: "in", weeklyOff: 5 });
    expect(mocks.revalidate.mock.calls.map(([path]) => path)).toEqual(["/team", "/employees/in", "/roster"]);
  });

  it("validates department size and malformed JSON instead of throwing", async () => {
    expect((await GET(readRequest(`?dept=${"x".repeat(129)}`))).status).toBe(400);
    const malformed = new NextRequest("https://hr.example/api/team/weekly-off", { method: "PATCH", body: "{" });
    expect((await PATCH(malformed)).status).toBe(400);
    expect(mocks.db.employee.updateMany).not.toHaveBeenCalled();
  });

  it("returns validation/not-found statuses from the shared mutation", async () => {
    expect((await PATCH(writeRequest({ employeeId: "in", weeklyOff: "2" }))).status).toBe(400);
    expect((await PATCH(writeRequest({ employeeId: "foreign", weeklyOff: 2 }))).status).toBe(404);
    expect(mocks.revalidate).not.toHaveBeenCalled();
  });

  it("returns retryable errors without serializing database details", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    mocks.db.employee.findMany.mockRejectedValueOnce(new Error("private database failure"));
    const read = await GET(readRequest());
    expect(read.status).toBe(500);
    expect(await read.json()).toEqual({ error: "Could not load Live Team. Try again." });
    mocks.db.employee.updateMany.mockRejectedValueOnce(new Error("private database failure"));
    const write = await PATCH(writeRequest({ employeeId: "in", weeklyOff: 4 }));
    expect(write.status).toBe(500);
    expect(await write.json()).toEqual({ error: "Could not save weekly off. Try again." });
    expect(mocks.revalidate).not.toHaveBeenCalled();
  });
});
