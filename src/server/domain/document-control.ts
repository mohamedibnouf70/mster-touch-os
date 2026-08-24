/** Pure document-control helpers (unit-testable, no DB). */

export function formatDocumentNumber(input: {
  projectCode: string;
  typeAbbr: string;
  disciplineCode: string;
  sequence: number;
  revision?: string;
}): string {
  if (!Number.isInteger(input.sequence) || input.sequence < 1) {
    throw new Error("sequence must be a positive integer");
  }
  const base = `MT-${input.projectCode}-${input.typeAbbr}-${input.disciplineCode.toUpperCase()}-${String(input.sequence).padStart(4, "0")}`;
  return input.revision ? `${base}-${input.revision}` : base;
}

export function nextRevisionCode(current: string | null | undefined): string {
  if (!current) return "R00";
  const match = current.match(/^R(\d+)$/i);
  if (match) {
    const next = Number(match[1]) + 1;
    return `R${String(next).padStart(2, "0")}`;
  }
  if (/^[A-Za-z]$/.test(current)) {
    return "R01";
  }
  return "R00";
}

export function isApprovedForExecution(decision: string | null | undefined, status?: string | null): boolean {
  if (status && ["resubmit", "rejected", "superseded", "draft"].includes(status)) {
    return false;
  }
  return decision === "A" || decision === "B";
}

export type ProjectHealth = "green" | "amber" | "red";

export type ProjectHealthSignals = {
  overdueRfis: number;
  overdueApprovals: number;
  openNcrs: number;
  criticalNcrs: number;
  failedInspections: number;
  lateStages: number;
  resubmitDocuments: number;
};

/**
 * Deterministic project health (documented rules):
 * RED: any critical open NCR OR overdue RFI >= 5 OR failed IR >= 3
 * AMBER: any open NCR / overdue item / late stage / resubmit / failed IR
 * GREEN: otherwise
 */
export function computeProjectHealth(signals: ProjectHealthSignals): ProjectHealth {
  if (signals.criticalNcrs > 0 || signals.overdueRfis >= 5 || signals.failedInspections >= 3) {
    return "red";
  }
  if (
    signals.openNcrs > 0 ||
    signals.overdueRfis > 0 ||
    signals.overdueApprovals > 0 ||
    signals.lateStages > 0 ||
    signals.resubmitDocuments > 0 ||
    signals.failedInspections > 0
  ) {
    return "amber";
  }
  return "green";
}

export const OFFICIAL_DECISIONS = ["A", "B", "C", "D", "E"] as const;
export type OfficialDecision = (typeof OFFICIAL_DECISIONS)[number];

export function requiresRevision(decision: OfficialDecision): boolean {
  return decision === "C";
}

export function blocksExecution(decision: OfficialDecision): boolean {
  return decision === "C" || decision === "D";
}
