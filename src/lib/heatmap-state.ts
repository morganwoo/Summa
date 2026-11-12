export const HEATMAP_DAYS = 90;
export const HABIT_COUNT = 3;

export function toggleLatestDay(completed: readonly boolean[], habitIndex: number): boolean[] {
  return completed.map((value, index) => index === habitIndex ? !value : value);
}