import { describe, expect, it } from "vitest";
import {
  blocksExecution,
  computeProjectHealth,
  formatDocumentNumber,
  isApprovedForExecution,
  nextRevisionCode,
  requiresRevision,
} from "@/server/domain/document-control";

describe("document numbering", () => {
  it("formats concurrency-safe document numbers", () => {
    expect(
      formatDocumentNumber({
        projectCode: "PRJ-0001",
        typeAbbr: "RFI",
        disciplineCode: "elec",
        sequence: 1,
        revision: "R00",
      }),
    ).toBe("MT-PRJ-0001-RFI-ELEC-0001-R00");
  });

  it("rejects invalid sequences", () => {
    expect(() =>
      formatDocumentNumber({
        projectCode: "PRJ-0001",
        typeAbbr: "MAT",
        disciplineCode: "HVAC",
        sequence: 0,
      }),
    ).toThrow();
  });
});

describe("revision control", () => {
  it("advances R00 → R01 → R02", () => {
    expect(nextRevisionCode(null)).toBe("R00");
    expect(nextRevisionCode("R00")).toBe("R01");
    expect(nextRevisionCode("R09")).toBe("R10");
  });

  it("maps legacy letter revisions into R-series", () => {
    expect(nextRevisionCode("A")).toBe("R01");
  });
});

describe("shop drawing execution eligibility", () => {
  it("allows A/B only", () => {
    expect(isApprovedForExecution("A")).toBe(true);
    expect(isApprovedForExecution("B")).toBe(true);
    expect(isApprovedForExecution("C")).toBe(false);
    expect(isApprovedForExecution("D")).toBe(false);
    expect(isApprovedForExecution("A", "superseded")).toBe(false);
  });
});

describe("approval decision helpers", () => {
  it("C requires revision; C/D block execution", () => {
    expect(requiresRevision("C")).toBe(true);
    expect(requiresRevision("A")).toBe(false);
    expect(blocksExecution("D")).toBe(true);
    expect(blocksExecution("B")).toBe(false);
  });
});

describe("project health", () => {
  it("returns green when clean", () => {
    expect(
      computeProjectHealth({
        overdueRfis: 0,
        overdueApprovals: 0,
        openNcrs: 0,
        criticalNcrs: 0,
        failedInspections: 0,
        lateStages: 0,
        resubmitDocuments: 0,
      }),
    ).toBe("green");
  });

  it("returns amber for overdue or open NCR", () => {
    expect(
      computeProjectHealth({
        overdueRfis: 1,
        overdueApprovals: 0,
        openNcrs: 0,
        criticalNcrs: 0,
        failedInspections: 0,
        lateStages: 0,
        resubmitDocuments: 0,
      }),
    ).toBe("amber");
  });

  it("returns red for critical NCR", () => {
    expect(
      computeProjectHealth({
        overdueRfis: 0,
        overdueApprovals: 0,
        openNcrs: 1,
        criticalNcrs: 1,
        failedInspections: 0,
        lateStages: 0,
        resubmitDocuments: 0,
      }),
    ).toBe("red");
  });
});
