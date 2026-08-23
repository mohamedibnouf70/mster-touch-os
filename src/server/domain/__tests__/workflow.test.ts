import { describe, expect, it } from "vitest";
import {
  applyWorkflowStepOutcome,
  canCompleteWorkflowStep,
  initialWorkflowStepStatuses,
  type WorkflowStepDefinition,
  type WorkflowStepRuntime,
} from "@/server/domain/workflow";

const definitions: WorkflowStepDefinition[] = [
  { id: "d1", key: "submit", sequence: 1, onRejectStepKey: null, onResubmitStepKey: null },
  { id: "d2", key: "review", sequence: 2, onRejectStepKey: "submit", onResubmitStepKey: "submit" },
  { id: "d3", key: "close", sequence: 3, onRejectStepKey: null, onResubmitStepKey: null },
];

function steps(statuses: Array<WorkflowStepRuntime["status"]>): WorkflowStepRuntime[] {
  return [
    { id: "s1", definitionStepId: "d1", key: "submit", sequence: 1, status: statuses[0]! },
    { id: "s2", definitionStepId: "d2", key: "review", sequence: 2, status: statuses[1]! },
    { id: "s3", definitionStepId: "d3", key: "close", sequence: 3, status: statuses[2]! },
  ];
}

describe("workflow engine", () => {
  it("starts with the first step ready", () => {
    const initial = initialWorkflowStepStatuses([
      { id: "s1", sequence: 1 },
      { id: "s2", sequence: 2 },
    ]);
    expect(initial).toEqual([
      { stepId: "s1", status: "ready" },
      { stepId: "s2", status: "pending" },
    ]);
  });

  it("advances to the next step on complete", () => {
    const result = applyWorkflowStepOutcome({
      instanceStatus: "in_progress",
      steps: steps(["ready", "pending", "pending"]),
      definitions,
      stepId: "s1",
      outcome: "complete",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.instanceStatus).toBe("in_progress");
    expect(result.updates).toContainEqual({ stepId: "s1", status: "completed" });
    expect(result.updates).toContainEqual({ stepId: "s2", status: "ready" });
  });

  it("rejects double completion of the same step", () => {
    expect(canCompleteWorkflowStep("completed")).toBe(false);
    const result = applyWorkflowStepOutcome({
      instanceStatus: "in_progress",
      steps: steps(["completed", "ready", "pending"]),
      definitions,
      stepId: "s1",
      outcome: "complete",
    });
    expect(result).toEqual({ ok: false, reason: "already_completed" });
  });

  it("follows resubmit path back to earlier step", () => {
    const result = applyWorkflowStepOutcome({
      instanceStatus: "in_progress",
      steps: steps(["completed", "in_progress", "pending"]),
      definitions,
      stepId: "s2",
      outcome: "resubmit",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.instanceStatus).toBe("in_progress");
    expect(result.updates.some((u) => u.stepId === "s1" && u.status === "ready")).toBe(true);
  });

  it("cancels remaining steps when reject has no target", () => {
    const result = applyWorkflowStepOutcome({
      instanceStatus: "in_progress",
      steps: steps(["ready", "pending", "pending"]),
      definitions,
      stepId: "s1",
      outcome: "reject",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.instanceStatus).toBe("cancelled");
    expect(result.updates).toContainEqual({ stepId: "s1", status: "rejected" });
  });
});
