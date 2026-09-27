import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  db: {
    employee: { findMany: vi.fn() },
    shift: { findMany: vi.fn() },
    shiftAssignment: { findMany: vi.fn(), upsert: vi.fn(), deleteMany: vi.fn() },
    department: { findMany: vi.fn() },
    shiftSwapRequest: { findMany: vi.fn() },
    $transaction: vi.fn(),
  },
  user: vi.fn(),
  revalidate: vi.fn(),
  getPerms: vi.fn(),
}));
vi.mock("@/lib/db", () => ({ db: mocks.db }));
vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidate }));
vi.mock("@/lib/api-auth", async (original) => ({
  ...await original<typeof import("@/lib/api-auth")>(), apiUser: mocks.user,
}));
vi.mock("@/lib/permissions", () => ({ getPerms: mocks.getPerms }));

import { getStaffRoster, isoDate, mondayOf, parseRosterWeek, rosterDate, saveStaffRoster } from "@/lib/roster";
import { GET, PATCH } from "@/app/api/roster/staff/route";

const now = new Date("2026-09-27T11:00:00Z"); // Sunday 16:30 IST
const stamp = (day: string) => new Date(`${day}T00:00:00Z`);
const staff = { id: "admin-1", companyId: "company-a", role: "ADMIN", employeeId: "in" };

const employee = (id: string, overrides: Record<string, unknown> = {}) => ({
  id, code: id.toUpperCase(), firstName: id, lastName: "Singh",
  companyId: "company-a", status: "ACTIVE", departmentId: "production",
  department: { name: "Production" },
  shift: { id: "general", name: "General", startTime: "08:00", durationH: 9 },
  baseSalary: 999999, bankAccount: "must-not-be-exposed",
  ...overrides,
});

let employees: ReturnType<typeof employee>[];

const readRequest = (query = "") => new NextRequest(`https://hr.example/api/roster/staff${query}`);
const writeRequest = (body: unknown) => new NextRequest("https://hr.example/api/roster/staff", {
  method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
});

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(now);
  vi.clearAllMocks();
  mocks.user.mockResolvedValue(staff);
  mocks.getPerms.mockResolvedValue({ canSwapShift: true });
  mocks.db.$transaction.mockImplementation(async (fn: (tx: typeof mocks.db) => unknown) => fn(mocks.db));
  employees = [
    employee("in"),
    employee("out", { departmentId: "quality", department: { name: "Quality" }, shift: { id: "night", name: "Night", startTime: "19:00", durationH: 12 } }),
    employee("inactive", { status: "INACTIVE" }),
    employee("foreign", { companyId: "company-b", departmentId: "foreign-dept", department: { name: "Private" } }),
  ];
  mocks.db.employee.findMany.mockImplementation(async ({ where, take }: { where: Record<string, unknown>; take?: number }) => {
    const notId = (where.id as { not?: string } | undefined)?.not;
    return employees.filter((e) =>
      e.companyId === where.companyId &&
      (!where.status || e.status === where.status) &&
      (!notId || e.id !== notId),
    ).slice(0, take ?? 999);
  });
  mocks.db.shift.findMany.mockResolvedValue([
    { id: "general", name: "General", startTime: "08:00", durationH: 9 },
    { id: "night", name: "Night", startTime: "19:00", durationH: 12 },
  ]);
  mocks.db.shiftAssignment.findMany.mockResolvedValue([
    { employeeId: "in", date: stamp("2026-09-23"), shiftId: null, isOff: true },
    { employeeId: "in", date: stamp("2026-09-25"), shiftId: "night", isOff: false },
  ]);
  mocks.db.department.findMany.mockResolvedValue([
    { id: "production", name: "Production" }, { id: "quality", name: "Quality" },
  ]);
  mocks.db.shiftSwapRequest.findMany.mockResolvedValue([
    {
      id: "swap-1", requesterId: "in", peerId: "out", date: stamp("2026-09-21"),
      note: "Family function", status: "PENDING",
      requester: { firstName: "in", lastName: "Singh" },
      peer: { firstName: "out", lastName: "Singh" },
    },
  ]);
  mocks.db.shiftAssignment.upsert.mockResolvedValue({});
  mocks.db.shiftAssignment.deleteMany.mockResolvedValue({ count: 1 });
});
afterEach(() => vi.useRealTimers());

describe("shared week/date rules", () => {
  it("uses plant midnight, not UTC or the phone's timezone", () => {
    expect(rosterDate(new Date("2026-09-26T18:29:59Z"))).toEqual(stamp("2026-09-26"));
    expect(rosterDate(new Date("2026-09-26T18:30:00Z"))).toEqual(stamp("2026-09-27"));
    expect(rosterDate(new Date("2026-12-31T18:30:00Z"))).toEqual(stamp("2027-01-01"));
  });

  it("anchors the week on Monday of the plant date", () => {
    expect(isoDate(mondayOf(stamp("2026-09-27")))).toBe("2026-09-21");
    expect(isoDate(mondayOf(stamp("2026-09-21")))).toBe("2026-09-21");
    expect(isoDate(mondayOf(stamp("2026-09-28")))).toBe("2026-09-28");
    expect(isoDate(parseRosterWeek(null, now)!)).toBe("2026-09-21");
    expect(isoDate(parseRosterWeek("2026-09-30", now)!)).toBe("2026-09-28");
    expect(parseRosterWeek("2026-13-40")).toBeNull();
    expect(parseRosterWeek("27-09-2026")).toBeNull();
  });
});

describe("staff roster snapshot", () => {
  it("returns only active employees in the company, default cells, and company-wide swaps", async () => {
    const data = await getStaffRoster("company-a", { now, viewerEmployeeId: "in" });
    expect(data.ok).toBe(true);
    if (!data.ok) return;
    expect(data.weekStart).toBe("2026-09-21");
    expect(data.weekEnd).toBe("2026-09-27");
    expect(data.today).toBe("2026-09-27");
    expect(data.timeZone).toBe("Asia/Kolkata");
    expect(data.days).toEqual(["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26", "2026-09-27"]);
    expect(data.employees.map((e) => e.id)).toEqual(["in", "out"]);
    expect(data.employees[0].cells["2026-09-21"]).toEqual({ shiftId: "", isOff: false });
    expect(data.employees[0].cells["2026-09-23"]).toEqual({ shiftId: "", isOff: true });
    expect(data.employees[0].cells["2026-09-25"]).toEqual({ shiftId: "night", isOff: false });
    expect(data.employees[0].cells["2026-09-27"].isOff).toBe(false); // Sunday is not auto-off on the staff board
    expect(data.swaps).toEqual([expect.objectContaining({
      id: "swap-1", requester: "in Singh", peer: "out Singh", date: "2026-09-21", mine: true, status: "PENDING",
    })]);
    expect(data.pendingSwapCount).toBe(1);
    expect(data.canSwap).toBe(true);
    expect(JSON.stringify(data)).not.toMatch(/bankAccount|baseSalary|must-not-be-exposed/);
    expect(mocks.db.shiftAssignment.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { companyId: "company-a", date: { gte: stamp("2026-09-21"), lte: stamp("2026-09-27") } },
    }));
  });

  it("never reveals another company's employees via a week or companyId", async () => {
    const data = await getStaffRoster("company-a", { week: "2026-09-21", now });
    expect(data.ok).toBe(true);
    if (!data.ok) return;
    expect(data.employees.map((e) => e.id)).not.toContain("foreign");
    expect(data.employees.map((e) => e.id)).not.toContain("inactive");
  });

  it("rejects an invalid week without touching the database", async () => {
    const data = await getStaffRoster("company-a", { week: "not-a-date", now });
    expect(data).toMatchObject({ ok: false, status: 400, error: "Invalid week." });
    expect(mocks.db.employee.findMany).not.toHaveBeenCalled();
  });
});

describe("roster save validation and persistence", () => {
  it("upserts an override, marks OFF, and deletes a cell restored to default", async () => {
    const result = await saveStaffRoster("company-a", { entries: [
      { employeeId: "in", date: "2026-09-22", shiftId: "night", isOff: false },
      { employeeId: "in", date: "2026-09-23", shiftId: null, isOff: true },
      { employeeId: "in", date: "2026-09-24", shiftId: null, isOff: false },
    ] });
    expect(result).toEqual({ ok: true, saved: 3 });
    expect(mocks.db.shiftAssignment.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { employeeId_date: { employeeId: "in", date: stamp("2026-09-22") } },
      update: { shiftId: "night", isOff: false },
    }));
    expect(mocks.db.shiftAssignment.upsert).toHaveBeenCalledWith(expect.objectContaining({
      update: { shiftId: null, isOff: true },
    }));
    expect(mocks.db.shiftAssignment.deleteMany).toHaveBeenCalledWith({
      where: { employeeId: "in", date: stamp("2026-09-24") },
    });
  });

  it("treats OFF as clearing any shift rather than keeping a leftover id", async () => {
    await saveStaffRoster("company-a", { entries: [
      { employeeId: "in", date: "2026-09-23", shiftId: "night", isOff: true },
    ] });
    expect(mocks.db.shiftAssignment.upsert).toHaveBeenCalledWith(expect.objectContaining({
      update: { shiftId: null, isOff: true },
    }));
  });

  it.each([
    null, [], {}, { entries: "nope" },
    { entries: [{ employeeId: "in", date: "2026-09-21", isOff: "true" }] },
    { entries: [{ employeeId: "in", date: "21-09-2026", isOff: false }] },
    { entries: [{ employeeId: "in", date: "2026-09-40", isOff: false }] },
    { entries: [{ employeeId: "", date: "2026-09-21", isOff: false }] },
    { entries: [{ employeeId: "in", date: "2026-09-21", isOff: false, extra: true }] },
  ])("rejects malformed input %j without a write", async (body) => {
    expect(await saveStaffRoster("company-a", body)).toMatchObject({ ok: false, status: 400 });
    expect(mocks.db.$transaction).not.toHaveBeenCalled();
  });

  it("does not convert an unknown shift into default", async () => {
    expect(await saveStaffRoster("company-a", { entries: [
      { employeeId: "in", date: "2026-09-22", shiftId: "missing-shift", isOff: false },
    ] })).toEqual({ ok: false, status: 400, error: "Unknown shift." });
    expect(mocks.db.$transaction).not.toHaveBeenCalled();
  });

  it.each(["foreign", "missing"])("returns the same 404 for \"%s\", without writing", async (id) => {
    expect(await saveStaffRoster("company-a", { entries: [
      { employeeId: id, date: "2026-09-22", shiftId: "general", isOff: false },
    ] })).toEqual({ ok: false, status: 404, error: "Employee not found." });
    expect(mocks.db.$transaction).not.toHaveBeenCalled();
  });

  it("allows an empty save as a no-op", async () => {
    expect(await saveStaffRoster("company-a", { entries: [] })).toEqual({ ok: true, saved: 0 });
    expect(mocks.db.$transaction).not.toHaveBeenCalled();
  });
});

describe("staff roster HTTP handlers", () => {
  it.each([null, { ...staff, role: "EMPLOYEE" }])("gates both endpoints before any data access (%j)", async (user) => {
    mocks.user.mockResolvedValue(user);
    const expected = user ? 403 : 401;
    expect((await GET(readRequest())).status).toBe(expected);
    expect((await PATCH(writeRequest({ entries: [] }))).status).toBe(expected);
    expect(mocks.db.employee.findMany).not.toHaveBeenCalled();
    expect(mocks.db.$transaction).not.toHaveBeenCalled();
  });

  it.each(["ADMIN", "HR"])("allows %s to read and update; invalidates the web view", async (role) => {
    mocks.user.mockResolvedValue({ ...staff, role });
    const response = await GET(readRequest("?w=2026-09-21&companyId=company-b"));
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    const body = await response.json();
    expect(body.employees.map((r: { id: string }) => r.id)).toEqual(["in", "out"]);
    expect(body.ok).toBeUndefined();
    const saved = await PATCH(writeRequest({
      entries: [{ employeeId: "in", date: "2026-09-22", shiftId: "night", isOff: false }],
    }));
    expect(saved.status).toBe(200);
    expect(await saved.json()).toEqual({ saved: 1 });
    expect(mocks.revalidate).toHaveBeenCalledWith("/roster");
  });

  it("validates week size and malformed JSON instead of throwing", async () => {
    expect((await GET(readRequest(`?w=${"x".repeat(33)}`))).status).toBe(400);
    expect((await GET(readRequest("?w=2026-09-99"))).status).toBe(400);
    const malformed = new NextRequest("https://hr.example/api/roster/staff", { method: "PATCH", body: "{" });
    expect((await PATCH(malformed)).status).toBe(400);
    expect(mocks.db.$transaction).not.toHaveBeenCalled();
  });

  it("returns validation/not-found statuses from the shared mutation", async () => {
    expect((await PATCH(writeRequest({ entries: [{ employeeId: "in", date: "2026-09-22", isOff: 0 }] }))).status).toBe(400);
    expect((await PATCH(writeRequest({ entries: [{ employeeId: "foreign", date: "2026-09-22", isOff: false }] }))).status).toBe(404);
    expect(mocks.revalidate).not.toHaveBeenCalled();
  });

  it("returns retryable errors without serializing database details", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    mocks.db.employee.findMany.mockRejectedValueOnce(new Error("private database failure"));
    const read = await GET(readRequest());
    expect(read.status).toBe(500);
    expect(await read.json()).toEqual({ error: "Could not load the duty roster. Try again." });
    mocks.db.$transaction.mockRejectedValueOnce(new Error("private database failure"));
    const write = await PATCH(writeRequest({
      entries: [{ employeeId: "in", date: "2026-09-22", shiftId: "general", isOff: false }],
    }));
    expect(write.status).toBe(500);
    expect(await write.json()).toEqual({ error: "Could not save the roster. Try again." });
    expect(mocks.revalidate).not.toHaveBeenCalled();
  });
});
