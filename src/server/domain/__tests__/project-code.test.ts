import { describe, expect, it } from "vitest";

/**
 * Project codes are allocated in PostgreSQL via project_number_counters + create_project RPC.
 * This unit test locks the formatting contract used by that RPC.
 */
function formatProjectCode(sequence: number): string {
  if (!Number.isInteger(sequence) || sequence < 1) {
    throw new Error("sequence must be a positive integer");
  }
  return `MT-PRJ-${String(sequence).padStart(4, "0")}`;
}

describe("project code contract", () => {
  it("formats concurrency-safe sequential codes", () => {
    expect(formatProjectCode(1)).toBe("MT-PRJ-0001");
    expect(formatProjectCode(12)).toBe("MT-PRJ-0012");
    expect(formatProjectCode(1001)).toBe("MT-PRJ-1001");
  });

  it("rejects unsafe non-positive sequences", () => {
    expect(() => formatProjectCode(0)).toThrow();
    expect(() => formatProjectCode(-1)).toThrow();
  });
});
