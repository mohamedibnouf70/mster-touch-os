export type OrganizationStatus = "active" | "suspended" | "archived";
export type MembershipStatus = "active" | "invited" | "suspended" | "removed";
export type EmploymentStatus = "active" | "on_leave" | "probation" | "terminated" | "resigned";
export type ProjectStatus = "draft" | "active" | "on_hold" | "completed" | "cancelled" | "archived";
export type ProjectPriority = "low" | "medium" | "high" | "critical";
export type RiskLevel = "low" | "medium" | "high" | "critical";
export type StageStatus =
  | "not_started"
  | "in_progress"
  | "blocked"
  | "completed"
  | "skipped"
  | "cancelled";
export type DocumentStatus =
  | "draft"
  | "submitted"
  | "under_review"
  | "approved"
  | "rejected"
  | "superseded"
  | "archived";
export type ConfidentialityLevel = "internal" | "confidential" | "restricted";
export type NotificationPriority = "low" | "normal" | "high" | "urgent";
export type NotificationChannel = "in_app" | "email" | "whatsapp" | "push";
export type Locale = "ar" | "en";

export const PROJECT_STATUSES: ProjectStatus[] = [
  "draft",
  "active",
  "on_hold",
  "completed",
  "cancelled",
  "archived",
];

export const RISK_LEVELS: RiskLevel[] = ["low", "medium", "high", "critical"];
