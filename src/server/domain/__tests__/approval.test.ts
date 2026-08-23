import { describe, expect, it } from "vitest";
import {
  applyApprovalDecision,
  decisionFromCode,
  DECISION_TO_CODE,
  isOfficialApprovalCode,
  OFFICIAL_APPROVAL_CODES,
  type ApprovalStepState,
} from "@/server/domain/approval";

const steps: ApprovalStepState[] = [
  { id: "a1", sequence: 1, status: "in_progress", actedBy: null },
  { id: "a2", sequence: 2, status: "pending", actedBy: null },
];

describe("approval engine", () => {
  it("maps official codes A–E", () => {
    expect(isOfficialApprovalCode("A")).toBe(true);
    expect(OFFICIAL_APPROVAL_CODES.A).toBe("approved");
    expect(decisionFromCode("D")).toBe("rejected");
    expect(DECISION_TO_CODE.approved_as_noted).toBe("B");
  });

  it("rejects unauthorized double decision on the same step", () => {
    const decided: ApprovalStepState[] = [
      { id: "a1", sequence: 1, status: "completed", actedBy: "user-1" },
      { id: "a2", sequence: 2, status: "in_progress", actedBy: null },
    ];
    const result = applyApprovalDecision({
      requestStatus: "in_progress",
      mode: "sequential",
      steps: decided,
      stepId: "a1",
      decision: "approved",
      actorId: "user-2",
    });
    expect(result).toEqual({ ok: false, reason: "already_decided" });
  });

  it("blocks acting on a non-current sequential step", () => {
    const result = applyApprovalDecision({
      requestStatus: "in_progress",
      mode: "sequential",
      steps,
      stepId: "a2",
      decision: "approved",
      actorId: "user-1",
    });
    expect(result).toEqual({ ok: false, reason: "not_current" });
  });

  it("completes request on rejection", () => {
    const result = applyApprovalDecision({
      requestStatus: "in_progress",
      mode: "sequential",
      steps,
      stepId: "a1",
      decision: "rejected",
      actorId: "user-1",
    });
    expect(result).toEqual({
      ok: true,
      stepStatus: "completed",
      requestStatus: "completed",
      nextStepId: null,
    });
  });

  it("advances to next step on approval when more steps remain", () => {
    const result = applyApprovalDecision({
      requestStatus: "in_progress",
      mode: "sequential",
      steps,
      stepId: "a1",
      decision: "approved",
      actorId: "user-1",
    });
    expect(result).toEqual({
      ok: true,
      stepStatus: "completed",
      requestStatus: "in_progress",
      nextStepId: "a2",
    });
  });
});
