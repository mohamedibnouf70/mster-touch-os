-- Master Touch OS — 010
-- Security-definer helpers and row-level security.
-- Helpers read authorization tables directly to avoid recursive RLS.

create or replace function public.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid();
$$;

create or replace function public.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.is_active = true
  );
$$;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.is_active = true
      and p.is_platform_admin = true
  );
$$;

create or replace function public.is_organization_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin()
    or exists (
      select 1
      from public.organization_members m
      join public.profiles p on p.id = m.profile_id
      where m.organization_id = p_organization_id
        and m.profile_id = auth.uid()
        and m.status = 'active'
        and p.is_active = true
    );
$$;

create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.organization_id
  from public.organization_members m
  where m.profile_id = auth.uid()
    and m.status = 'active'
  order by m.joined_at
  limit 1;
$$;

create or replace function public.has_permission(
  p_permission_key text,
  p_organization_id uuid,
  p_scope_type public.role_scope_type default 'organization',
  p_scope_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin()
    or exists (
      select 1
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      join public.role_permissions rp on rp.role_id = r.id
      join public.profiles p on p.id = ur.profile_id
      join public.organization_members m
        on m.profile_id = ur.profile_id
       and m.organization_id = ur.organization_id
      where ur.profile_id = auth.uid()
        and ur.organization_id = p_organization_id
        and rp.permission_key = p_permission_key
        and r.is_external = false
        and p.is_active = true
        and m.status = 'active'
        and (
          ur.scope_type = 'organization'
          or (
            p_scope_type = ur.scope_type
            and p_scope_id is not null
            and ur.scope_id = p_scope_id
          )
        )
    );
$$;

create or replace function public.can_access_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.projects pr
    where pr.id = p_project_id
      and (
        public.is_platform_admin()
        or (
          public.is_organization_member(pr.organization_id)
          and (
            public.has_permission('project.read', pr.organization_id, 'organization', null)
            or public.has_permission('project.read', pr.organization_id, 'project', pr.id)
            or pr.project_manager_id = auth.uid()
            or exists (
              select 1
              from public.project_members pm
              where pm.project_id = pr.id
                and pm.profile_id = auth.uid()
                and pm.is_active = true
            )
          )
        )
      )
  );
$$;

grant execute on function public.current_profile_id() to authenticated;
grant execute on function public.is_active_profile() to authenticated;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.is_organization_member(uuid) to authenticated;
grant execute on function public.current_organization_id() to authenticated;
grant execute on function public.has_permission(text, uuid, public.role_scope_type, uuid) to authenticated;
grant execute on function public.can_access_project(uuid) to authenticated;

create or replace function public.log_audit(
  p_organization_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_previous_values jsonb default null,
  p_new_values jsonb default null,
  p_ip_address text default null,
  p_user_agent text default null,
  p_correlation_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.audit_logs (
    organization_id, actor_id, action, entity_type, entity_id,
    previous_values, new_values, ip_address, user_agent, correlation_id
  ) values (
    p_organization_id, auth.uid(), p_action, p_entity_type, p_entity_id,
    p_previous_values, p_new_values, p_ip_address, p_user_agent, p_correlation_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.emit_domain_event(
  p_organization_id uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb default '{}'::jsonb,
  p_correlation_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.domain_events (
    organization_id, event_type, entity_type, entity_id, actor_id, payload, correlation_id
  ) values (
    p_organization_id, p_event_type, p_entity_type, p_entity_id, auth.uid(), p_payload, p_correlation_id
  ) returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.log_audit(uuid, text, text, uuid, jsonb, jsonb, text, text, text) to authenticated;
grant execute on function public.emit_domain_event(uuid, text, text, uuid, jsonb, text) to authenticated;

-- Enable RLS on every business table.
alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_members enable row level security;
alter table public.departments enable row level security;
alter table public.employees enable row level security;
alter table public.employee_departments enable row level security;
alter table public.employee_compliance enable row level security;
alter table public.employee_compensation enable row level security;
alter table public.hr_alert_hooks enable row level security;
alter table public.permissions enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.clients enable row level security;
alter table public.project_counters enable row level security;
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.employee_project_assignments enable row level security;
alter table public.project_stage_templates enable row level security;
alter table public.project_stage_template_items enable row level security;
alter table public.project_stages enable row level security;
alter table public.project_stage_dependencies enable row level security;
alter table public.workflow_definitions enable row level security;
alter table public.workflow_versions enable row level security;
alter table public.workflow_steps enable row level security;
alter table public.workflow_step_rules enable row level security;
alter table public.workflow_instances enable row level security;
alter table public.workflow_instance_steps enable row level security;
alter table public.approval_requests enable row level security;
alter table public.approval_steps enable row level security;
alter table public.approval_actions enable row level security;
alter table public.document_categories enable row level security;
alter table public.documents enable row level security;
alter table public.document_versions enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_deliveries enable row level security;
alter table public.audit_logs enable row level security;
alter table public.domain_events enable row level security;

-- Organizations
create policy organizations_select on public.organizations
  for select to authenticated
  using (public.is_organization_member(id));

create policy organizations_update on public.organizations
  for update to authenticated
  using (public.has_permission('organization.update', id))
  with check (public.has_permission('organization.update', id));

-- Profiles
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_platform_admin()
    or exists (
      select 1
      from public.organization_members mine
      join public.organization_members other
        on other.organization_id = mine.organization_id
      where mine.profile_id = auth.uid()
        and mine.status = 'active'
        and other.profile_id = profiles.id
    )
  );

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and is_platform_admin = profiles.is_platform_admin);

-- Memberships
create policy organization_members_select on public.organization_members
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy organization_members_write on public.organization_members
  for all to authenticated
  using (public.has_permission('user.update', organization_id))
  with check (public.has_permission('user.update', organization_id));

-- Departments
create policy departments_select on public.departments
  for select to authenticated
  using (public.has_permission('department.read', organization_id) or public.is_organization_member(organization_id));

create policy departments_insert on public.departments
  for insert to authenticated
  with check (public.has_permission('department.create', organization_id));

create policy departments_update on public.departments
  for update to authenticated
  using (public.has_permission('department.update', organization_id))
  with check (public.has_permission('department.update', organization_id));

-- Employees
create policy employees_select on public.employees
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.has_permission('employee.read', organization_id)
  );

create policy employees_write on public.employees
  for all to authenticated
  using (public.has_permission('employee.manage', organization_id))
  with check (public.has_permission('employee.manage', organization_id));

create policy employee_departments_select on public.employee_departments
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy employee_departments_write on public.employee_departments
  for all to authenticated
  using (public.has_permission('employee.manage', organization_id))
  with check (public.has_permission('employee.manage', organization_id));

create policy employee_compliance_select on public.employee_compliance
  for select to authenticated
  using (public.has_permission('employee.read', organization_id));

create policy employee_compliance_write on public.employee_compliance
  for all to authenticated
  using (public.has_permission('employee.manage', organization_id))
  with check (public.has_permission('employee.manage', organization_id));

create policy employee_compensation_all on public.employee_compensation
  for all to authenticated
  using (
    public.has_permission('finance.manage', organization_id)
    or public.has_permission('employee.manage', organization_id)
  )
  with check (
    public.has_permission('finance.manage', organization_id)
    or public.has_permission('employee.manage', organization_id)
  );

create policy hr_alert_hooks_select on public.hr_alert_hooks
  for select to authenticated
  using (public.has_permission('employee.read', organization_id));

-- RBAC catalogs
create policy permissions_select on public.permissions
  for select to authenticated
  using (public.is_active_profile());

create policy roles_select on public.roles
  for select to authenticated
  using (organization_id is null or public.is_organization_member(organization_id));

create policy role_permissions_select on public.role_permissions
  for select to authenticated
  using (public.is_active_profile());

create policy user_roles_select on public.user_roles
  for select to authenticated
  using (profile_id = auth.uid() or public.has_permission('user.read', organization_id));

create policy user_roles_write on public.user_roles
  for all to authenticated
  using (public.has_permission('role.assign', organization_id))
  with check (public.has_permission('role.assign', organization_id));

-- Projects
create policy clients_select on public.clients
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy project_counters_all on public.project_counters
  for all to authenticated
  using (public.has_permission('project.create', organization_id))
  with check (public.has_permission('project.create', organization_id));

create policy projects_select on public.projects
  for select to authenticated
  using (public.can_access_project(id));

create policy projects_insert on public.projects
  for insert to authenticated
  with check (public.has_permission('project.create', organization_id));

create policy projects_update on public.projects
  for update to authenticated
  using (
    public.has_permission('project.update', organization_id)
    or public.has_permission('project.archive', organization_id)
    or project_manager_id = auth.uid()
  )
  with check (public.is_organization_member(organization_id));

create policy project_members_select on public.project_members
  for select to authenticated
  using (public.can_access_project(project_id));

create policy project_members_write on public.project_members
  for all to authenticated
  using (public.has_permission('project.manage_team', organization_id))
  with check (public.has_permission('project.manage_team', organization_id));

create policy employee_project_assignments_select on public.employee_project_assignments
  for select to authenticated
  using (public.can_access_project(project_id) or public.has_permission('employee.read', organization_id));

create policy employee_project_assignments_write on public.employee_project_assignments
  for all to authenticated
  using (public.has_permission('project.manage_team', organization_id))
  with check (public.has_permission('project.manage_team', organization_id));

create policy project_stage_templates_select on public.project_stage_templates
  for select to authenticated
  using (organization_id is null or public.is_organization_member(organization_id));

create policy project_stage_template_items_select on public.project_stage_template_items
  for select to authenticated
  using (exists (
    select 1 from public.project_stage_templates t
    where t.id = template_id
      and (t.organization_id is null or public.is_organization_member(t.organization_id))
  ));

create policy project_stages_select on public.project_stages
  for select to authenticated
  using (public.can_access_project(project_id));

create policy project_stages_write on public.project_stages
  for all to authenticated
  using (public.has_permission('project.update', organization_id))
  with check (public.has_permission('project.update', organization_id));

create policy project_stage_dependencies_select on public.project_stage_dependencies
  for select to authenticated
  using (public.can_access_project(project_id));

-- Workflows
create policy workflow_definitions_select on public.workflow_definitions
  for select to authenticated
  using (organization_id is null or public.is_organization_member(organization_id));

create policy workflow_versions_select on public.workflow_versions
  for select to authenticated
  using (exists (
    select 1 from public.workflow_definitions d
    where d.id = definition_id
      and (d.organization_id is null or public.is_organization_member(d.organization_id))
  ));

create policy workflow_steps_select on public.workflow_steps
  for select to authenticated
  using (exists (
    select 1
    from public.workflow_versions v
    join public.workflow_definitions d on d.id = v.definition_id
    where v.id = version_id
      and (d.organization_id is null or public.is_organization_member(d.organization_id))
  ));

create policy workflow_step_rules_select on public.workflow_step_rules
  for select to authenticated
  using (exists (select 1 from public.workflow_steps s where s.id = step_id));

create policy workflow_instances_select on public.workflow_instances
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy workflow_instances_write on public.workflow_instances
  for all to authenticated
  using (
    public.has_permission('workflow.start', organization_id)
    or public.has_permission('workflow.advance', organization_id)
    or public.has_permission('workflow.manage', organization_id)
  )
  with check (
    public.has_permission('workflow.start', organization_id)
    or public.has_permission('workflow.manage', organization_id)
  );

create policy workflow_instance_steps_select on public.workflow_instance_steps
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy workflow_instance_steps_write on public.workflow_instance_steps
  for all to authenticated
  using (
    public.has_permission('workflow.advance', organization_id)
    or public.has_permission('workflow.manage', organization_id)
  )
  with check (
    public.has_permission('workflow.advance', organization_id)
    or public.has_permission('workflow.manage', organization_id)
  );

-- Approvals
create policy approval_requests_select on public.approval_requests
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy approval_requests_insert on public.approval_requests
  for insert to authenticated
  with check (public.has_permission('approval.create', organization_id));

create policy approval_requests_update on public.approval_requests
  for update to authenticated
  using (
    public.has_permission('approval.review', organization_id)
    or public.has_permission('approval.approve', organization_id)
  )
  with check (public.is_organization_member(organization_id));

create policy approval_steps_select on public.approval_steps
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy approval_steps_write on public.approval_steps
  for all to authenticated
  using (
    public.has_permission('approval.create', organization_id)
    or public.has_permission('approval.review', organization_id)
    or public.has_permission('approval.approve', organization_id)
  )
  with check (public.is_organization_member(organization_id));

create policy approval_actions_select on public.approval_actions
  for select to authenticated
  using (public.is_organization_member(organization_id));

create policy approval_actions_insert on public.approval_actions
  for insert to authenticated
  with check (
    public.has_permission('approval.approve', organization_id)
    or public.has_permission('approval.reject', organization_id)
    or public.has_permission('approval.review', organization_id)
  );

-- Documents
create policy document_categories_select on public.document_categories
  for select to authenticated
  using (public.is_active_profile());

create policy documents_select on public.documents
  for select to authenticated
  using (
    public.has_permission('document.read', organization_id)
    or (project_id is not null and public.can_access_project(project_id))
  );

create policy documents_insert on public.documents
  for insert to authenticated
  with check (public.has_permission('document.upload', organization_id));

create policy documents_update on public.documents
  for update to authenticated
  using (public.has_permission('document.update', organization_id) or public.has_permission('document.approve', organization_id))
  with check (public.is_organization_member(organization_id));

create policy document_versions_select on public.document_versions
  for select to authenticated
  using (public.has_permission('document.read', organization_id));

create policy document_versions_insert on public.document_versions
  for insert to authenticated
  with check (public.has_permission('document.upload', organization_id));

-- Notifications: recipient only
create policy notifications_select on public.notifications
  for select to authenticated
  using (recipient_profile_id = auth.uid());

create policy notifications_update on public.notifications
  for update to authenticated
  using (recipient_profile_id = auth.uid())
  with check (recipient_profile_id = auth.uid());

create policy notification_deliveries_select on public.notification_deliveries
  for select to authenticated
  using (exists (
    select 1 from public.notifications n
    where n.id = notification_id and n.recipient_profile_id = auth.uid()
  ));

-- Audit is insert-only via log_audit(); no client writes.
create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using (public.has_permission('audit.read', organization_id));

create policy domain_events_select on public.domain_events
  for select to authenticated
  using (public.has_permission('audit.read', organization_id) or public.has_permission('workflow.manage', organization_id));
