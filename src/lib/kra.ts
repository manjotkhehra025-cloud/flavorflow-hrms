/** Live auto-score: Σ min(100, achieved/target×100) × weight → points out of Σweights (usually 100). */
export function kraScoreOf(goals: { weight: number; target: number; achieved: number }[]) {
  let points = 0;
  let totalWeight = 0;
  for (const g of goals) {
    totalWeight += g.weight;
    const pct = g.target > 0 ? Math.min(100, (g.achieved / g.target) * 100) : g.achieved > 0 ? 100 : 0;
    points += (pct * g.weight) / 100;
  }
  const max = totalWeight || 100;
  return { points: Math.round(points * 10) / 10, max, pct: Math.round((points / max) * 1000) / 10 };
}

export function kraGoalPct(target: number, achieved: number): number {
  if (target <= 0) return achieved > 0 ? 100 : 0;
  return Math.min(100, Math.round((achieved / target) * 1000) / 10);
}

export function currentQuarter(d = new Date()): { year: number; quarter: number } {
  return { year: d.getFullYear(), quarter: Math.floor(d.getMonth() / 3) + 1 };
}
