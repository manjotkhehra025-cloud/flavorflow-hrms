import { createHmac } from "crypto";

/**
 * Rotating, HMAC-signed gate QR token (P4).
 * Format: HM1:<empCode>:<win>:<mac>
 *   win = seconds-since-epoch / 30 (integer) — a token is valid for its window
 *   plus one extra window (60s worst case), so a phone scan at the edge still passes.
 *   mac = first 10 base36 chars of HMAC-SHA256(AUTH_SECRET, "HM1|<empCode>|<win>")
 */
const ALGO = "sha256";
const WIN_SECS = 30;

function key(): string {
  const s = process.env.AUTH_SECRET;
  if (!s) throw new Error("AUTH_SECRET is not set");
  return s;
}

function macFor(code: string, win: number): string {
  const mac = createHmac(ALGO, key()).update(`HM1|${code}|${win}`).digest();
  // fold the 32-byte digest into a short base36 string (10 chars ≈ 52 bits)
  let n = BigInt("0x" + mac.subarray(0, 7).toString("hex"));
  return n.toString(36).padStart(10, "0").slice(0, 10);
}

export interface GateQr {
  token: string;
  win: number;
  refreshInSec: number; // seconds until the next window roll
}

export function makeGateQr(empCode: string, now = new Date()): GateQr {
  const epoch = Math.floor(now.getTime() / 1000);
  const win = Math.floor(epoch / WIN_SECS);
  const refreshInSec = WIN_SECS - (epoch % WIN_SECS);
  return { token: `HM1:${empCode}:${win}:${macFor(empCode, win)}`, win, refreshInSec };
}

/** Returns the employee code if the token is structurally valid & inside its window. */
export function verifyGateQr(token: string, now = new Date()): { code: string } | null {
  const parts = token.trim().split(":");
  if (parts.length !== 4 || parts[0] !== "HM1") return null;
  const [, code, winStr, mac] = parts;
  const win = Number(winStr);
  if (!Number.isInteger(win)) return null;
  if (mac !== macFor(code, win)) return null;
  const cur = Math.floor(now.getTime() / 1000 / WIN_SECS);
  if (win !== cur && win !== cur - 1) return null; // current window or the one just ended
  return { code };
}
