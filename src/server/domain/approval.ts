export const OFFICIAL_APPROVAL_CODES = {
  A: "approved",
  B: "approved_as_noted",
  C: "resubmit",
  D: "rejected",
  E: "for_information",
} as const;

export type OfficialApprovalCode = keyof typeof OFFICIAL_APPROVAL_CODES;
export type ApprovalDecision = (typeof OFFICIAL_APPROVAL_CODES)[OfficialApprovalCode];
export type ApprovalRequestStatus = "pending" | "in_progress" | "completed" | "cancelled";
export type ApprovalStepStatus = "pending" | "in_progress" | "completed" | "skipped" | "cancelled";
export type ApprovalMode = "sequential" | "parallel";

export const DECISION_TO_CODE: Record<ApprovalDecision, OfficialApprovalCode> = {
  approved: "A",
  approved_as_noted: "B",
  resubmit: "C",
  rejected: "D",
  for_information: "E",
};

export const TERMINAL_DECISIONS: readonly ApprovalDecision[] = [
  "approved",
  "approved_as_noted",
  "resubmit",
  "rejected",
  "for_information",
];

export type ApprovalStepState = {
  id: string;
  sequence: number;
  status: ApprovalStepStatus;
  actedBy: string | null;
};

export type ApprovalTransitionResult =
  | { ok: true; stepStatus: ApprovalStepStatus; requestStatus: ApprovalRequestStatus; nextStepId: string | null }
  | { ok: false; reason: "already_decided" | "not_current" | "invalid_decision" | "cancelled" };

export function isOfficialApprovalCode(value: string): value is OfficialApprovalCode {
  return value in OFFICIAL_APPROVAL_CODES;
}

export function decisionFromCode(code: OfficialApprovalCode): ApprovalDecision {
  return OFFICIAL_APPROVAL_CODES[code];
}

export function isTerminalDecision(value: string): value is ApprovalDecision {
  return TERMINAL_DECISIONS.includes(value as ApprovalDecision);
}

export function applyApprovalDecision(input: {
  requestStatus: ApprovalRequestStatus;
  mode: ApprovalMode;
  steps: ApprovalStepState[];
  stepId: string;
  decision: ApprovalDecision;
  actorId: string;
}): ApprovalTransitionResult {
  if (input.requestStatus === "cancelled" || input.requestStatus === "completed") {
    return { ok: false, reason: "cancelled" };
  }

  if (!isTerminalDecision(input.decision)) {
    return { ok: false, reason: "invalid_decision" };
  }

  const step = input.steps.find((item) => item.id === input.stepId);
  if (!step) {
    return { ok: false, reason: "not_current" };
  }

  if (step.status === "completed" || step.actedBy) {
    return { ok: false, reason: "already_decided" };
  }

  if (step.status === "cancelled" || step.status === "skipped") {
    return { ok: false, reason: "not_current" };
  }

  if (input.mode === "sequential") {
    const current = [...input.steps]
      .sort((a, b) => a.sequence - b.sequence)
      .find((item) => item.status === "pending" || item.status === "in_progress");

    if (!current || current.id !== step.id) {
      return { ok: false, reason: "not_current" };
    }
  }

  const isBlockingRejection = input.decision === "rejected" || input.decision === "resubmit";
  const remaining = input.steps.filter(
    (item) => item.id !== step.id && (item.status === "pending" || item.status === "in_progress"),
  );

  if (isBlockingRejection) {
    return {
      ok: true,
      stepStatus: "completed",
      requestStatus: "completed",
      nextStepId: null,
    };
  }

  if (remaining.length === 0) {
    return {
      ok: true,
      stepStatus: "completed",
      requestStatus: "completed",
      nextStepId: null,
    };
  }

  const next = remaining.sort((a, b) => a.sequence - b.sequence)[0] ?? null;

  return {
    ok: true,
    stepStatus: "completed",
    requestStatus: "in_progress",
    nextStepId: input.mode === "sequential" ? next?.id ?? null : null,
  };
}
