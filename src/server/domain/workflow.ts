export type WorkflowInstanceStatus = "pending" | "in_progress" | "completed" | "cancelled";
export type WorkflowStepStatus =
  | "pending"
  | "ready"
  | "in_progress"
  | "completed"
  | "skipped"
  | "rejected"
  | "cancelled";

export type WorkflowOutcome = "complete" | "reject" | "resubmit";

export type WorkflowStepDefinition = {
  id: string;
  key: string;
  sequence: number;
  onRejectStepKey: string | null;
  onResubmitStepKey: string | null;
};

export type WorkflowStepRuntime = {
  id: string;
  definitionStepId: string;
  key: string;
  sequence: number;
  status: WorkflowStepStatus;
};

export type WorkflowTransitionResult =
  | {
      ok: true;
      instanceStatus: WorkflowInstanceStatus;
      updates: Array<{ stepId: string; status: WorkflowStepStatus }>;
    }
  | { ok: false; reason: "already_completed" | "not_active" | "invalid_outcome" | "cancelled" };

export function canCompleteWorkflowStep(status: WorkflowStepStatus): boolean {
  return status === "ready" || status === "in_progress";
}

export function applyWorkflowStepOutcome(input: {
  instanceStatus: WorkflowInstanceStatus;
  steps: WorkflowStepRuntime[];
  definitions: WorkflowStepDefinition[];
  stepId: string;
  outcome: WorkflowOutcome;
}): WorkflowTransitionResult {
  if (input.instanceStatus === "cancelled") {
    return { ok: false, reason: "cancelled" };
  }
  if (input.instanceStatus === "completed") {
    return { ok: false, reason: "already_completed" };
  }

  const current = input.steps.find((step) => step.id === input.stepId);
  if (!current) {
    return { ok: false, reason: "not_active" };
  }

  if (!canCompleteWorkflowStep(current.status)) {
    return { ok: false, reason: current.status === "completed" ? "already_completed" : "not_active" };
  }

  const definition = input.definitions.find((item) => item.id === current.definitionStepId);
  const updates: Array<{ stepId: string; status: WorkflowStepStatus }> = [];

  if (input.outcome === "reject") {
    updates.push({ stepId: current.id, status: "rejected" });
    const targetKey = definition?.onRejectStepKey;
    if (!targetKey) {
      for (const step of input.steps) {
        if (step.id !== current.id && (step.status === "pending" || step.status === "ready" || step.status === "in_progress")) {
          updates.push({ stepId: step.id, status: "cancelled" });
        }
      }
      return { ok: true, instanceStatus: "cancelled", updates };
    }
    return activateFromKey(input.steps, targetKey, updates, "rejected");
  }

  if (input.outcome === "resubmit") {
    updates.push({ stepId: current.id, status: "completed" });
    const targetKey = definition?.onResubmitStepKey;
    if (!targetKey) {
      return { ok: false, reason: "invalid_outcome" };
    }
    return resetFromKey(input.steps, current.sequence, targetKey, updates);
  }

  updates.push({ stepId: current.id, status: "completed" });
  const next = input.steps
    .filter((step) => step.sequence > current.sequence && step.status === "pending")
    .sort((a, b) => a.sequence - b.sequence)[0];

  if (!next) {
    return { ok: true, instanceStatus: "completed", updates };
  }

  updates.push({ stepId: next.id, status: "ready" });
  return { ok: true, instanceStatus: "in_progress", updates };
}

function activateFromKey(
  steps: WorkflowStepRuntime[],
  key: string,
  updates: Array<{ stepId: string; status: WorkflowStepStatus }>,
  currentStatus: WorkflowStepStatus,
): WorkflowTransitionResult {
  const target = steps.find((step) => step.key === key);
  if (!target) {
    return { ok: false, reason: "invalid_outcome" };
  }
  updates.push({ stepId: target.id, status: "ready" });
  void currentStatus;
  return { ok: true, instanceStatus: "in_progress", updates };
}

function resetFromKey(
  steps: WorkflowStepRuntime[],
  currentSequence: number,
  key: string,
  updates: Array<{ stepId: string; status: WorkflowStepStatus }>,
): WorkflowTransitionResult {
  const target = steps.find((step) => step.key === key);
  if (!target) {
    return { ok: false, reason: "invalid_outcome" };
  }

  for (const step of steps) {
    if (step.sequence >= target.sequence && step.sequence < currentSequence) {
      updates.push({ stepId: step.id, status: step.id === target.id ? "ready" : "pending" });
    }
  }

  if (!updates.some((item) => item.stepId === target.id)) {
    updates.push({ stepId: target.id, status: "ready" });
  }

  return { ok: true, instanceStatus: "in_progress", updates };
}

export function initialWorkflowStepStatuses(
  steps: Array<{ id: string; sequence: number }>,
): Array<{ stepId: string; status: WorkflowStepStatus }> {
  const ordered = [...steps].sort((a, b) => a.sequence - b.sequence);
  return ordered.map((step, index) => ({
    stepId: step.id,
    status: index === 0 ? "ready" : "pending",
  }));
}
