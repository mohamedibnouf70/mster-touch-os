import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { DatabaseError } from "@/lib/errors";
import type {
  AuditLogRecord,
  DashboardStats,
  Department,
  DocumentRecord,
  Employee,
  NotificationRecord,
  PendingAction,
  Profile,
  Project,
  ProjectStage,
} from "@/types/models";

function fail(error: { message?: string } | null): never {
  throw new DatabaseError(error);
}

export class CoreRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  async listDepartments(organizationId: string): Promise<Department[]> {
    const { data, error } = await this.supabase
      .from("departments")
      .select("*")
      .eq("organization_id", organizationId)
      .order("name_ar");
    if (error) fail(error);
    return (data ?? []) as Department[];
  }

  async listEmployees(organizationId: string): Promise<Array<Employee & { profiles: Profile | null }>> {
    const { data, error } = await this.supabase
      .from("employees")
      .select("*, profiles(*)")
      .eq("organization_id", organizationId)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) fail(error);
    return (data ?? []) as Array<Employee & { profiles: Profile | null }>;
  }

  async getEmployee(organizationId: string, employeeId: string) {
    const { data, error } = await this.supabase
      .from("employees")
      .select("*, profiles(*), employee_departments(*, departments(*)), employee_project_assignments(*)")
      .eq("organization_id", organizationId)
      .eq("id", employeeId)
      .maybeSingle();
    if (error) fail(error);
    return data;
  }

  async listProjects(input: {
    organizationId: string;
    search?: string;
    status?: string;
    risk?: string;
    managerId?: string;
    page: number;
    pageSize: number;
  }): Promise<{ rows: Project[]; total: number }> {
    let query = this.supabase
      .from("projects")
      .select("*", { count: "exact" })
      .eq("organization_id", input.organizationId)
      .is("archived_at", null)
      .order("created_at", { ascending: false })
      .range((input.page - 1) * input.pageSize, input.page * input.pageSize - 1);

    if (input.search) {
      query = query.or(`name_ar.ilike.%${input.search}%,name_en.ilike.%${input.search}%,project_code.ilike.%${input.search}%`);
    }
    if (input.status) {
      query = query.eq("status", input.status);
    }
    if (input.risk) {
      query = query.eq("risk_level", input.risk);
    }
    if (input.managerId) {
      query = query.eq("project_manager_id", input.managerId);
    }

    const { data, error, count } = await query;
    if (error) fail(error);
    return { rows: (data ?? []) as Project[], total: count ?? 0 };
  }

  async getProject(organizationId: string, projectId: string): Promise<Project | null> {
    const { data, error } = await this.supabase
      .from("projects")
      .select("*")
      .eq("organization_id", organizationId)
      .eq("id", projectId)
      .maybeSingle<Project>();
    if (error) fail(error);
    return data;
  }

  async listProjectStages(projectId: string): Promise<ProjectStage[]> {
    const { data, error } = await this.supabase
      .from("project_stages")
      .select("*")
      .eq("project_id", projectId)
      .order("sequence");
    if (error) fail(error);
    return (data ?? []) as ProjectStage[];
  }

  async listProjectMembers(projectId: string) {
    const { data, error } = await this.supabase
      .from("project_members")
      .select("*, profiles(*)")
      .eq("project_id", projectId)
      .eq("is_active", true);
    if (error) fail(error);
    return data ?? [];
  }

  async listDocuments(organizationId: string, projectId?: string): Promise<DocumentRecord[]> {
    let query = this.supabase
      .from("documents")
      .select("*")
      .eq("organization_id", organizationId)
      .order("created_at", { ascending: false })
      .limit(50);
    if (projectId) {
      query = query.eq("project_id", projectId);
    }
    const { data, error } = await query;
    if (error) fail(error);
    return (data ?? []) as DocumentRecord[];
  }

  async listDocumentVersions(documentId: string) {
    const { data, error } = await this.supabase
      .from("document_versions")
      .select("*")
      .eq("document_id", documentId)
      .order("uploaded_at", { ascending: false });
    if (error) fail(error);
    return data ?? [];
  }

  async listApprovals(organizationId: string) {
    const { data, error } = await this.supabase
      .from("approval_requests")
      .select("*, approval_steps(*)")
      .eq("organization_id", organizationId)
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) fail(error);
    return data ?? [];
  }

  async listNotifications(profileId: string): Promise<NotificationRecord[]> {
    const { data, error } = await this.supabase
      .from("notifications")
      .select("*")
      .eq("recipient_profile_id", profileId)
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) fail(error);
    return (data ?? []) as NotificationRecord[];
  }

  async listAudit(organizationId: string, limit = 20): Promise<AuditLogRecord[]> {
    const { data, error } = await this.supabase
      .from("audit_logs")
      .select("*")
      .eq("organization_id", organizationId)
      .order("created_at", { ascending: false })
      .limit(limit);
    if (error) fail(error);
    return (data ?? []) as AuditLogRecord[];
  }

  async listUsers(organizationId: string) {
    const { data, error } = await this.supabase
      .from("organization_members")
      .select("*, profiles(*), employees(*)")
      .eq("organization_id", organizationId)
      .order("joined_at", { ascending: false })
      .limit(100);
    if (error) fail(error);
    return data ?? [];
  }

  async listRoles() {
    const { data, error } = await this.supabase
      .from("roles")
      .select("*")
      .eq("is_system", true)
      .order("name_ar");
    if (error) fail(error);
    return data ?? [];
  }

  async dashboard(organizationId: string, profileId: string): Promise<{
    stats: DashboardStats;
    pendingActions: PendingAction[];
    recentActivity: AuditLogRecord[];
  }> {
    const now = new Date().toISOString();
    const [
      activeProjects,
      projectsAtRisk,
      pendingApprovals,
      overdueApprovals,
      activeEmployees,
      unreadNotifications,
      myApprovalSteps,
      myWorkflowSteps,
      myRfis,
      myNcrs,
      revisionDocs,
      myInspections,
      recentActivity,
    ] = await Promise.all([
      this.supabase
        .from("projects")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .eq("status", "active"),
      this.supabase
        .from("projects")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .eq("status", "active")
        .in("risk_level", ["high", "critical"]),
      this.supabase
        .from("approval_requests")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .in("status", ["pending", "in_progress"]),
      this.supabase
        .from("approval_requests")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .in("status", ["pending", "in_progress"])
        .lt("due_at", now),
      this.supabase
        .from("employees")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .eq("is_active", true),
      this.supabase
        .from("notifications")
        .select("id", { count: "exact", head: true })
        .eq("recipient_profile_id", profileId)
        .is("read_at", null),
      this.supabase
        .from("approval_steps")
        .select("id, due_at, request_id, approval_requests(title, entity_type, entity_id)")
        .eq("organization_id", organizationId)
        .eq("user_id", profileId)
        .in("status", ["pending", "in_progress"])
        .limit(10),
      this.supabase
        .from("workflow_instance_steps")
        .select("id, due_at, step_key, instance_id")
        .eq("organization_id", organizationId)
        .eq("assigned_user_id", profileId)
        .in("status", ["ready", "in_progress"])
        .limit(10),
      this.supabase
        .from("rfis")
        .select("id, rfi_number, subject, response_required_by, status, priority")
        .eq("organization_id", organizationId)
        .eq("responsible_engineer_id", profileId)
        .in("status", ["draft", "internal_review", "submitted", "under_review", "answered"])
        .limit(15),
      this.supabase
        .from("ncrs")
        .select("id, ncr_number, description, severity, status, target_closure_date")
        .eq("organization_id", organizationId)
        .or(`assigned_to.eq.${profileId},responsible_person_id.eq.${profileId}`)
        .neq("status", "closed")
        .limit(15),
      this.supabase
        .from("documents")
        .select("id, document_number, title, official_decision, response_due_at")
        .eq("organization_id", organizationId)
        .eq("responsible_engineer_id", profileId)
        .in("official_decision", ["C", "D"])
        .limit(15),
      this.supabase
        .from("inspection_requests")
        .select("id, ir_number, related_activity, status, inspection_date_requested")
        .eq("organization_id", organizationId)
        .or(`site_engineer_id.eq.${profileId},quality_engineer_id.eq.${profileId},requested_by.eq.${profileId}`)
        .in("status", ["ready", "submitted", "scheduled", "failed", "reinspection_required"])
        .limit(15),
      this.supabase
        .from("audit_logs")
        .select("*")
        .eq("organization_id", organizationId)
        .order("created_at", { ascending: false })
        .limit(8),
    ]);

    const pendingActions: PendingAction[] = [];
    for (const row of myApprovalSteps.data ?? []) {
      const request = Array.isArray(row.approval_requests)
        ? row.approval_requests[0]
        : row.approval_requests;
      pendingActions.push({
        id: row.id,
        kind: "approval",
        title: request?.title ?? "موافقة",
        entityType: request?.entity_type ?? "approval",
        entityId: request?.entity_id ?? row.request_id,
        dueAt: row.due_at,
        isOverdue: Boolean(row.due_at && row.due_at < now),
        priority: 2,
      });
    }
    for (const row of myWorkflowSteps.data ?? []) {
      pendingActions.push({
        id: row.id,
        kind: "workflow",
        title: row.step_key,
        entityType: "workflow_instance_step",
        entityId: row.instance_id,
        dueAt: row.due_at,
        isOverdue: Boolean(row.due_at && row.due_at < now),
        priority: 3,
      });
    }
    for (const row of myRfis.data ?? []) {
      const overdue = Boolean(
        row.response_required_by &&
          row.response_required_by < now &&
          ["submitted", "under_review"].includes(row.status),
      );
      pendingActions.push({
        id: row.id,
        kind: "rfi",
        title: `${row.rfi_number} — ${row.subject}`,
        entityType: "rfi",
        entityId: row.id,
        dueAt: row.response_required_by,
        isOverdue: overdue,
        priority: row.priority === "critical" ? 0 : overdue ? 1 : 4,
      });
    }
    for (const row of myNcrs.data ?? []) {
      const overdue = Boolean(
        row.target_closure_date && row.target_closure_date < now.slice(0, 10),
      );
      pendingActions.push({
        id: row.id,
        kind: "ncr",
        title: `${row.ncr_number} — ${row.description.slice(0, 60)}`,
        entityType: "ncr",
        entityId: row.id,
        dueAt: row.target_closure_date,
        isOverdue: overdue,
        priority: row.severity === "critical" ? 0 : overdue ? 1 : 3,
      });
    }
    for (const row of revisionDocs.data ?? []) {
      pendingActions.push({
        id: row.id,
        kind: "document_revision",
        title: `${row.document_number} — مراجعة مطلوبة (${row.official_decision})`,
        entityType: "document",
        entityId: row.id,
        dueAt: row.response_due_at,
        isOverdue: Boolean(row.response_due_at && row.response_due_at < now),
        priority: row.official_decision === "D" ? 1 : 2,
      });
    }
    for (const row of myInspections.data ?? []) {
      pendingActions.push({
        id: row.id,
        kind: "inspection",
        title: `${row.ir_number} — ${row.related_activity ?? row.status}`,
        entityType: "inspection_request",
        entityId: row.id,
        dueAt: row.inspection_date_requested,
        isOverdue: ["failed", "reinspection_required"].includes(row.status),
        priority: row.status === "failed" ? 1 : 3,
      });
    }

    pendingActions.sort((a, b) => {
      if (a.isOverdue !== b.isOverdue) return a.isOverdue ? -1 : 1;
      return (a.priority ?? 5) - (b.priority ?? 5);
    });

    return {
      stats: {
        activeProjects: activeProjects.count ?? 0,
        projectsAtRisk: projectsAtRisk.count ?? 0,
        pendingApprovals: pendingApprovals.count ?? 0,
        overdueApprovals: overdueApprovals.count ?? 0,
        activeEmployees: activeEmployees.count ?? 0,
        unreadNotifications: unreadNotifications.count ?? 0,
      },
      pendingActions: pendingActions.slice(0, 25),
      recentActivity: (recentActivity.data ?? []) as AuditLogRecord[],
    };
  }
}
