export const DOMAIN_EVENTS = [
  "project.created",
  "project.updated",
  "project.archived",
  "project.stage.started",
  "project.stage.completed",
  "project.member.assigned",
  "project.health_changed",
  "approval.created",
  "approval.overdue",
  "approval.approved",
  "approval.rejected",
  "approval.resubmitted",
  "document.uploaded",
  "document.registered",
  "document.revised",
  "document.submitted",
  "document.approved",
  "document.resubmit_required",
  "document.rejected",
  "workflow.started",
  "workflow.step.completed",
  "workflow.cancelled",
  "employee.created",
  "employee.assigned",
  "employee.deactivated",
  "user.role.changed",
  "user.deactivated",
  "rfi.created",
  "rfi.submitted",
  "rfi.answered",
  "rfi.overdue",
  "inspection.submitted",
  "inspection.failed",
  "inspection.passed",
  "ncr.created",
  "ncr.critical",
  "ncr.closed",
  "ncr.reopened",
  "transmittal.issued",
] as const;

export type DomainEventType = (typeof DOMAIN_EVENTS)[number];

export type DomainEvent<TPayload extends Record<string, unknown> = Record<string, unknown>> = {
  type: DomainEventType;
  organizationId: string;
  actorId: string | null;
  entityType: string;
  entityId: string;
  payload: TPayload;
  correlationId: string;
  occurredAt: string;
};
