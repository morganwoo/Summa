import { describe, expect, it } from "vitest";
import { HEATMAP_DAYS, toggleLatestDay } from "@/lib/heatmap-state";

describe("heatmap completion", () => {
  it("marks the latest day in all three heatmaps together", () => {
    expect(toggleLatestDay([false, false, false])).toEqual([true, true, true]);
  });
  it("allows clearing the latest day in all three heatmaps together", () => {
    expect(toggleLatestDay([true, true, true])).toEqual([false, false, false]);
  });
  it("keeps a ninety-day program", () => {
    expect(HEATMAP_DAYS).toBe(90);
  });
});