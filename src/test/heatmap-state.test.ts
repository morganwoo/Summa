import { describe, expect, it } from "vitest";
import { HEATMAP_DAYS, toggleLatestDay } from "@/lib/heatmap-state";

describe("heatmap completion", () => {
  it.each([0, 1, 2])("changes only the assigned heatmap for button %i", (index) => {
    const expected = [false, false, false];
    expected[index] = true;
    expect(toggleLatestDay([false, false, false], index)).toEqual(expected);
  });
  it("clears only the assigned heatmap without changing the others", () => {
    expect(toggleLatestDay([true, true, true], 1)).toEqual([true, false, true]);
  });
  it("keeps a ninety-day program", () => {
    expect(HEATMAP_DAYS).toBe(90);
  });
});