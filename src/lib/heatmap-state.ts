export const HEATMAP_DAYS = 90;
export const HABIT_COUNT = 3;

export function toggleLatestDay(completed: readonly boolean[]): boolean[] {
  const next = !completed.every(Boolean);
  return Array.from({ length: HABIT_COUNT }, () => next);
}