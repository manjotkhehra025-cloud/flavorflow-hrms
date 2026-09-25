import { after } from "next/server";
import { SignJWT, importPKCS8 } from "jose";
import { db } from "@/lib/db";
import { routeGroup, groupHeadExists } from "@/lib/approve-routing";

/**
 * P6 — FCM push (HTTP v1).
 *
 * Config: env `FCM_SERVICE_ACCOUNT` = the Firebase service-account JSON
 * (raw JSON or base64 of it). Missing/invalid → every send is a silent no-op,
 * so the web app and the in-app bell keep working without Firebase.
 */

export type PushMessage = {
  title: string;
  body: string;
  /** Flutter route to open on tap: `tab:approvals` | `tab:leaves` | `/attendance` | … */
  appPath?: string;
  kind?: string;
};

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

let cachedAccount: ServiceAccount | null | undefined;
let cachedToken: { value: string; exp: number } | null = null;

function serviceAccount(): ServiceAccount | null {
  if (cachedAccount !== undefined) return cachedAccount;
  const raw = process.env.FCM_SERVICE_ACCOUNT?.trim();
  cachedAccount = null;
  if (!raw) return null;
  try {
    const text = raw.startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8");
    const j = JSON.parse(text) as Partial<ServiceAccount>;
    if (j.project_id && j.client_email && j.private_key) {
      cachedAccount = { project_id: j.project_id, client_email: j.client_email, private_key: j.private_key };
    }
  } catch {
    console.warn("[push] FCM_SERVICE_ACCOUNT is not valid JSON/base64 — push disabled");
  }
  return cachedAccount;
}

export function pushEnabled(): boolean {
  return serviceAccount() !== null;
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.value;
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`oauth ${res.status}`);
  const j = (await res.json()) as { access_token: string; expires_in: number };
  cachedToken = { value: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return j.access_token;
}

/** Send to raw device tokens; prunes tokens FCM reports as dead. */
async function sendToTokens(tokens: string[], msg: PushMessage): Promise<number> {
  const sa = serviceAccount();
  if (!sa || tokens.length === 0) return 0;
  const bearer = await accessToken(sa);
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  const dead: string[] = [];
  let sent = 0;
  await Promise.all(
    tokens.map(async (token) => {
      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: msg.title, body: msg.body },
            data: { appPath: msg.appPath ?? "/home", kind: msg.kind ?? "" },
            android: { priority: "HIGH", notification: { sound: "default" } },
          },
        }),
      });
      if (res.ok) {
        sent++;
        return;
      }
      const text = await res.text().catch(() => "");
      if (res.status === 404 || /UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT/.test(text)) {
        dead.push(token);
      } else {
        console.warn(`[push] FCM ${res.status}: ${text.slice(0, 200)}`);
      }
    }),
  );
  if (dead.length) await db.pushToken.deleteMany({ where: { token: { in: dead } } });
  return sent;
}

export async function pushToUsers(userIds: string[], msg: PushMessage): Promise<number> {
  if (!pushEnabled() || userIds.length === 0) return 0;
  const rows = await db.pushToken.findMany({ where: { userId: { in: [...new Set(userIds)] } }, select: { token: true } });
  return sendToTokens(rows.map((r) => r.token), msg);
}

/**
 * Run a push after the response is sent — never slows or fails the request.
 * Falls back to a detached promise outside a request scope (scripts).
 */
export function queuePush(job: () => Promise<unknown>) {
  if (!pushEnabled()) return;
  const run = () => job().catch((e) => console.warn("[push] failed:", e instanceof Error ? e.message : e));
  try {
    after(run);
  } catch {
    void run();
  }
}

/** Login(s) linked to an employee profile. */
async function userIdsForEmployee(employeeId: string): Promise<string[]> {
  const users = await db.user.findMany({ where: { employeeId, isActive: true }, select: { id: true } });
  return users.map((u) => u.id);
}

/**
 * Who should hear "new request" — mirrors approve-routing:
 * route A → Senior Manager(s), route B → AGM(s); vacant head or no route →
 * ADMIN/HR (super-admin fallback). The requester never pings themselves.
 */
export async function approverUserIds(companyId: string, requesterEmployeeId: string): Promise<string[]> {
  const emp = await db.employee.findFirst({
    where: { id: requesterEmployeeId, companyId },
    include: { department: { include: { parent: true } } },
  });
  if (!emp) return [];
  const group = routeGroup(emp as never);
  let users: { id: string }[] = [];
  if (group && (await groupHeadExists(companyId, group))) {
    users = await db.user.findMany({
      where: {
        companyId,
        isActive: true,
        employee: {
          status: "ACTIVE",
          id: { not: requesterEmployeeId },
          designation: {
            title: { contains: group === "A" ? "Senior Manager" : "Assistant General Manager", mode: "insensitive" },
          },
        },
      },
      select: { id: true },
    });
  }
  if (users.length === 0) {
    users = await db.user.findMany({
      where: { companyId, isActive: true, role: { in: ["ADMIN", "HR"] }, NOT: { employeeId: requesterEmployeeId } },
      select: { id: true },
    });
  }
  return users.map((u) => u.id);
}

const KIND_TITLE: Record<string, string> = {
  leave: "Leave request",
  punch: "Manual punch / OT",
  gate: "Gate pass",
  swap: "Shift swap",
};

/** "Approval arrived" → routed approvers. */
export function notifyNewRequest(
  companyId: string,
  requesterEmployeeId: string,
  kind: "leave" | "punch" | "gate" | "swap",
  detail: string,
) {
  queuePush(async () => {
    const [ids, emp] = await Promise.all([
      approverUserIds(companyId, requesterEmployeeId),
      db.employee.findUnique({ where: { id: requesterEmployeeId }, select: { firstName: true, lastName: true } }),
    ]);
    const who = emp ? `${emp.firstName} ${emp.lastName}`.trim() : "Employee";
    await pushToUsers(ids, {
      title: `New ${KIND_TITLE[kind] ?? "request"}`,
      body: `${who} · ${detail}`,
      appPath: "tab:approvals",
      kind: `new_${kind}`,
    });
  });
}

/** "Your request was decided" → the requester. */
export function notifyDecision(
  requesterEmployeeId: string,
  kind: "leave" | "punch" | "gate" | "swap",
  approved: boolean,
  detail: string,
) {
  queuePush(async () => {
    const ids = await userIdsForEmployee(requesterEmployeeId);
    const appPath = kind === "leave" ? "tab:leaves" : kind === "gate" ? "/idcard" : kind === "swap" ? "/roster" : "/attendance";
    await pushToUsers(ids, {
      title: `${KIND_TITLE[kind] ?? "Request"} ${approved ? "approved ✔" : "declined ✖"}`,
      body: detail,
      appPath,
      kind: `decided_${kind}`,
    });
  });
}
