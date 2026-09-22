export const CATEGORY_META: Record<string, { emoji: string; label: string }> = {
  MACHINE: { emoji: "🔧", label: "Machine" },
  SALARY: { emoji: "💰", label: "Salary" },
  UNIFORM: { emoji: "👕", label: "Uniform" },
  CANTEEN: { emoji: "🍽️", label: "Canteen" },
  SAFETY: { emoji: "🦺", label: "Safety" },
  OTHER: { emoji: "＋", label: "Other" },
};

export const TICKET_TONE: Record<string, "blue" | "amber" | "green" | "slate"> = {
  OPEN: "blue",
  IN_PROGRESS: "amber",
  RESOLVED: "green",
  CLOSED: "slate",
};
