import type { PermissionKey } from "@/lib/permissions/catalog";
import type { RoleScopeType } from "@/lib/permissions/evaluate";
import type {
  ConfidentialityLevel,
  DocumentStatus,
  EmploymentStatus,
  Locale,
  MembershipStatus,
  NotificationPriority,
  OrganizationStatus,
  ProjectPriority,
  ProjectStatus,
  RiskLevel,
  StageStatus,
} from "./enums";

export type Organization = {
  id: string;
  name_ar: string;
  name_en: string;
  legal_name: string | null;
  commercial_registration: string | null;
  vat_number: string | null;
  logo_path: string | null;
  country: string;
  timezone: string;
  default_currency: string;
  status: OrganizationStatus;
  created_at: string;
  updated_at: string;
};

export type Department = {
  id: string;
  organization_id: string;
  code: string;
  name_ar: string;
  name_en: string;
  description: string | null;
  parent_department_id: string | null;
  manager_user_id: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type Profile = {
  id: string;
  full_name_ar: string;
  full_name_en: string;
  phone: string | null;
  locale: Locale;
  is_active: boolean;
  is_platform_admin: boolean;
  avatar_path: string | null;
  last_seen_at: string | null;
  created_at: string;
  updated_at: string;
};

export type Employee = {
  id: string;
  organization_id: string;
  profile_id: string;
  employee_number: string | null;
  job_title_ar: string | null;
  job_title_en: string | null;
  employment_status: EmploymentStatus;
  joining_date: string | null;
  contract_start: string | null;
  contract_end: string | null;
  probation_end: string | null;
  direct_manager_employee_id: string | null;
  work_location: string | null;
  nationality: string | null;
  is_active: boolean;
  terminated_at: string | null;
  created_at: string;
  updated_at: string;
};

export type AuthContext = {
  userId: string;
  profile: Profile;
  organization: Organization;
  employee: Employee | null;
  membershipStatus: MembershipStatus;
  grants: Array<{
    roleCode: string;
    isExternal: boolean;
    organizationId: string;
    scopeType: RoleScopeType;
    scopeId: string | null;
    permissions: readonly PermissionKey[];
  }>;
  permissions: PermissionKey[];
};

export type Project = {
  id: string;
  organization_id: string;
  project_code: string;
  name_ar: string;
  name_en: string;
  description: string | null;
  client_id: string | null;
  project_manager_id: string | null;
  status: ProjectStatus;
  priority: ProjectPriority;
  start_date: string | null;
  planned_end_date: string | null;
  actual_end_date: string | null;
  contract_value: number | null;
  budget: number | null;
  progress_percentage: number;
  risk_level: RiskLevel;
  location: string | null;
  business_case_document_id: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  archived_at: string | null;
};

export type ProjectStage = {
  id: string;
  project_id: string;
  organization_id: string;
  template_item_id: string | null;
  name_ar: string;
  name_en: string;
  sequence: number;
  owner_user_id: string | null;
  department_id: string | null;
  planned_start: string | null;
  planned_end: string | null;
  actual_start: string | null;
  actual_end: string | null;
  status: StageStatus;
  progress_percentage: number;
  requires_approval: boolean;
  sla_hours: number | null;
  due_at: string | null;
  warning_at: string | null;
  overdue_at: string | null;
  escalation_level: number;
  escalated_at: string | null;
  risk_level: RiskLevel;
  created_at: string;
  updated_at: string;
};

export type DocumentRecord = {
  id: string;
  organization_id: string;
  project_id: string | null;
  category: string;
  document_number: string | null;
  title: string;
  current_revision: string;
  status: DocumentStatus;
  discipline: string | null;
  confidentiality: ConfidentialityLevel;
  approval_state: string;
  uploaded_by: string;
  created_at: string;
  updated_at: string;
};

export type NotificationRecord = {
  id: string;
  organization_id: string;
  recipient_profile_id: string;
  type: string;
  title: string;
  message: string;
  entity_type: string | null;
  entity_id: string | null;
  priority: NotificationPriority;
  read_at: string | null;
  created_at: string;
};

export type AuditLogRecord = {
  id: string;
  organization_id: string;
  actor_id: string | null;
  action: string;
  entity_type: string;
  entity_id: string;
  previous_values: Record<string, unknown> | null;
  new_values: Record<string, unknown> | null;
  ip_address: string | null;
  user_agent: string | null;
  correlation_id: string | null;
  created_at: string;
};

export type DashboardStats = {
  activeProjects: number;
  projectsAtRisk: number;
  pendingApprovals: number;
  overdueApprovals: number;
  activeEmployees: number;
  unreadNotifications: number;
};

export type PendingAction = {
  id: string;
  kind:
    | "approval"
    | "workflow"
    | "rfi"
    | "document_revision"
    | "ncr"
    | "inspection"
    | "correspondence";
  title: string;
  entityType: string;
  entityId: string;
  dueAt: string | null;
  isOverdue: boolean;
  priority?: number;
};
