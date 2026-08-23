export const DOMAIN_EVENTS = [
  "project.created",
  "project.updated",
  "project.archived",
  "project.stage.started",
  "project.stage.completed",
  "project.member.assigned",
  "approval.created",
  "approval.overdue",
  "approval.approved",
  "approval.rejected",
  "approval.resubmitted",
  "document.uploaded",
  "document.revised",
  "workflow.started",
  "workflow.step.completed",
  "workflow.cancelled",
  "employee.created",
  "employee.assigned",
  "employee.deactivated",
  "user.role.changed",
  "user.deactivated",
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
