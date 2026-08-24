# Database

## Migration order

Apply in numeric order under `supabase/migrations/`:

| File | Purpose |
| --- | --- |
| `001_extensions_and_types.sql` | pgcrypto, pg_trgm, enums, `set_updated_at` |
| `002_organizations.sql` | organizations |
| `003_identity_and_hr.sql` | profiles, membership, departments, employees, HR alert hooks |
| `004_rbac.sql` | roles, permissions, role_permissions, user_roles |
| `005_projects.sql` | projects, stages, templates, members, counters |
| `006_workflows.sql` | definitions, versions, steps, instances |
| `007_approvals.sql` | approval_requests, steps, actions |
| `008_documents.sql` | documents, document_versions, categories |
| `009_notifications_audit_events.sql` | notifications, audit_logs, domain_events |
| `010_functions_rls.sql` | security helpers + RLS policies |
| `011_rpc.sql` | atomic RPCs (project create, workflow, approval) |
| `012_storage.sql` | private bucket + storage policies |
| `013_seed_system.sql` | Master Touch org, departments, RBAC, templates |
| `014_assignee_enforcement.sql` | Approval/workflow assignee enforcement on RPCs |
| `015_engineering_disciplines.sql` | Disciplines + project_disciplines |
| `016_document_control.sql` | Register metadata, R00 numbering |
| `017_rfi.sql` | RFI module |
| `018_material_submittals.sql` | Material submittals |
| `019_shop_drawings.sql` | Shop drawings + AFE guard |
| `020_method_statements.sql` | Method statements |
| `021_inspection_requests.sql` | Inspection requests |
| `022_ncr.sql` | NCR |
| `023_reports_correspondence.sql` | Reports + correspondence |
| `024_contacts_transmittals.sql` | Contacts + immutable transmittals |
| `025_phase2_rbac.sql` | Phase 2 permissions + project.read_all |
| `026_phase2_rls.sql` | Phase 2 RLS + scoped project access |
| `027_phase2_rpc.sql` | Register/revise/approve/issue/health RPCs |
| `028_phase2_indexes_workflows.sql` | Indexes + workflow seeds |

Development-only seeds (fake users/finance) must **never** live in `013`. Add a separate `9xx_dev_seed.sql` if needed.

## Core entities

### Organization & identity

- `organizations`
- `profiles` ↔ `auth.users.id`
- `organization_members`
- `departments`
- `employees`
- `employee_departments`
- `employee_project_assignments`
- `employee_compliance_documents` / obligation alert fields (Phase 5 hooks)

### RBAC

- `roles` (system + org-scoped; `is_external` for future portals)
- `permissions` (resource.action keys)
- `role_permissions`
- `user_roles` with `scope_type` + `scope_id`

### Projects

- `projects` — unique `(organization_id, project_code)`
- `project_number_counters` — concurrency-safe codes (`MT-PRJ-0001`)
- `project_stage_templates` / `project_stage_template_items`
- `project_stages`
- `project_members`

### Workflows

- `workflow_definitions`
- `workflow_versions` (immutable once published/used)
- `workflow_steps` / `workflow_step_rules`
- `workflow_instances` / `workflow_instance_steps`

### Approvals & SLA

- `approval_requests` — execution status ≠ decision
- `approval_steps` — assignee + `due_at` / `warning_at` / escalation fields
- `approval_actions` — immutable decision history (codes A–E)

### Documents

- `documents` — category, revision pointer, confidentiality
- `document_versions` — never overwrite prior revision blobs

### Platform

- `notifications`
- `audit_logs` (append-oriented; no update/delete policies for normal roles)
- `domain_events`

## Project code generation

Do **not** use `MAX(code)+1`. RPC `create_project` locks/increments `project_number_counters` per organization inside a transaction.

## Soft delete / archive

Prefer `archived_at`, `is_active`, status enums. Historical employees and approvals are retained.

## Indexes (selected)

Organization, project, assignee, status, due_at, created_at, department_id, workflow instance, approval status — see migration DDL.
