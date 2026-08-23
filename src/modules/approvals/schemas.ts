import { z } from "zod";

export const createApprovalSchema = z.object({
  title: z.string().trim().min(2).max(240),
  entityType: z.string().min(2).max(60),
  entityId: z.string().uuid(),
  approverProfileId: z.string().uuid(),
  dueAt: z.string().optional(),
});

export const decideApprovalSchema = z.object({
  stepId: z.string().uuid(),
  officialCode: z.enum(["A", "B", "C", "D", "E"]),
  comment: z.string().trim().max(2000).optional(),
});

export const startWorkflowSchema = z.object({
  definitionId: z.string().uuid(),
  entityType: z.string().min(2).max(60),
  entityId: z.string().uuid(),
});

export const completeWorkflowStepSchema = z.object({
  instanceStepId: z.string().uuid(),
  outcome: z.enum(["complete", "reject", "resubmit"]),
});
