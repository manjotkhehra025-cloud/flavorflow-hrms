import { db } from "@/lib/db";

/** Per-employee feature permissions — super admin toggles each from the profile. */
export type PermKey =
  | "canPunch"
  | "canApplyLeave"
  | "canGatePass"
  | "canSwapShift"
  | "canSocialPost"
  | "canViewPayslip";

export const DEFAULT_PERMS: Record<PermKey, boolean> = {
  canPunch: true,
  canApplyLeave: true,
  canGatePass: true,
  canSwapShift: true,
  canSocialPost: true,
  canViewPayslip: true,
};

export async function getPerms(employeeId: string | null | undefined): Promise<Record<PermKey, boolean>> {
  if (!employeeId) return { ...DEFAULT_PERMS };
  const row = await db.employeePermission.findUnique({ where: { employeeId } });
  if (!row) return { ...DEFAULT_PERMS };
  return {
    canPunch: row.canPunch,
    canApplyLeave: row.canApplyLeave,
    canGatePass: row.canGatePass,
    canSwapShift: row.canSwapShift,
    canSocialPost: row.canSocialPost,
    canViewPayslip: row.canViewPayslip,
  };
}

/** Guard: returns error message when the employee is BANNED from a feature (null = allowed). */
export async function permDenied(employeeId: string | null | undefined, key: PermKey): Promise<string | null> {
  const perms = await getPerms(employeeId);
  if (perms[key]) return null;
  const names: Record<PermKey, string> = {
    canPunch: "self punch",
    canApplyLeave: "leave requests",
    canGatePass: "gate passes",
    canSwapShift: "shift swaps",
    canSocialPost: "Social Wall posting",
    canViewPayslip: "payslip viewing",
  };
  return `${names[key]} is turned OFF for you — ask the super admin to allow it.`;
}
