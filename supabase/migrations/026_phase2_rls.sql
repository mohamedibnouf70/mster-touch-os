-- Master Touch OS — 026
-- Phase 2 RLS + tightened project-scoped access (project.read_all).

-- Tighten can_access_project: org-scoped project.read alone is insufficient.
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
            public.has_permission('project.read_all', pr.organization_id, 'organization', null)
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

-- Helper: project-scoped module permission
create or replace function public.has_project_permission(
  p_permission_key text,
  p_project_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.projects pr
    where pr.id = p_project_id
      and (
        public.is_platform_admin()
        or (
          public.can_access_project(p_project_id)
          and (
            public.has_permission(p_permission_key, pr.organization_id, 'organization', null)
            or public.has_permission(p_permission_key, pr.organization_id, 'project', pr.id)
          )
        )
      )
  );
$$;

grant execute on function public.has_project_permission(text, uuid) to authenticated;

-- Enable RLS on Phase 2 tables
alter table public.engineering_disciplines enable row level security;
alter table public.project_disciplines enable row level security;
alter table public.document_type_codes enable row level security;
alter table public.document_number_counters enable row level security;
alter table public.rfis enable row level security;
alter table public.material_submittals enable row level security;
alter table public.shop_drawings enable row level security;
alter table public.method_statements enable row level security;
alter table public.inspection_requests enable row level security;
alter table public.ncrs enable row level security;
alter table public.project_reports enable row level security;
alter table public.correspondence enable row level security;
alter table public.project_contacts enable row level security;
alter table public.transmittals enable row level security;
alter table public.transmittal_items enable row level security;

drop policy if exists engineering_disciplines_select on public.engineering_disciplines;
create policy engineering_disciplines_select on public.engineering_disciplines
  for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists engineering_disciplines_write on public.engineering_disciplines;
create policy engineering_disciplines_write on public.engineering_disciplines
  for all to authenticated
  using (public.has_permission('engineering.manage', organization_id))
  with check (public.has_permission('engineering.manage', organization_id));

drop policy if exists project_disciplines_select on public.project_disciplines;
create policy project_disciplines_select on public.project_disciplines
  for select to authenticated
  using (public.can_access_project(project_id));

drop policy if exists project_disciplines_write on public.project_disciplines;
create policy project_disciplines_write on public.project_disciplines
  for all to authenticated
  using (public.has_project_permission('engineering.manage', project_id)
    or public.has_project_permission('project.update', project_id))
  with check (public.has_project_permission('engineering.manage', project_id)
    or public.has_project_permission('project.update', project_id));

drop policy if exists document_type_codes_select on public.document_type_codes;
create policy document_type_codes_select on public.document_type_codes
  for select to authenticated
  using (public.is_active_profile());

drop policy if exists document_number_counters_all on public.document_number_counters;
create policy document_number_counters_all on public.document_number_counters
  for all to authenticated
  using (public.has_permission('document_control.register', organization_id)
    or public.has_permission('document.upload', organization_id))
  with check (public.has_permission('document_control.register', organization_id)
    or public.has_permission('document.upload', organization_id));

-- Generic project-scoped policies for operational modules
drop policy if exists rfis_select on public.rfis;
create policy rfis_select on public.rfis
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('rfi.read', project_id));

drop policy if exists rfis_insert on public.rfis;
create policy rfis_insert on public.rfis
  for insert to authenticated
  with check (public.has_project_permission('rfi.create', project_id));

drop policy if exists rfis_update on public.rfis;
create policy rfis_update on public.rfis
  for update to authenticated
  using (
    public.has_project_permission('rfi.update', project_id)
    or public.has_project_permission('rfi.respond', project_id)
    or public.has_project_permission('rfi.close', project_id)
    or public.has_project_permission('rfi.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists material_submittals_select on public.material_submittals;
create policy material_submittals_select on public.material_submittals
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('submittal.read', project_id));

drop policy if exists material_submittals_insert on public.material_submittals;
create policy material_submittals_insert on public.material_submittals
  for insert to authenticated
  with check (public.has_project_permission('submittal.create', project_id));

drop policy if exists material_submittals_update on public.material_submittals;
create policy material_submittals_update on public.material_submittals
  for update to authenticated
  using (
    public.has_project_permission('submittal.update', project_id)
    or public.has_project_permission('submittal.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists shop_drawings_select on public.shop_drawings;
create policy shop_drawings_select on public.shop_drawings
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('shop_drawing.read', project_id));

drop policy if exists shop_drawings_insert on public.shop_drawings;
create policy shop_drawings_insert on public.shop_drawings
  for insert to authenticated
  with check (public.has_project_permission('shop_drawing.create', project_id));

drop policy if exists shop_drawings_update on public.shop_drawings;
create policy shop_drawings_update on public.shop_drawings
  for update to authenticated
  using (
    public.has_project_permission('shop_drawing.update', project_id)
    or public.has_project_permission('shop_drawing.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists method_statements_select on public.method_statements;
create policy method_statements_select on public.method_statements
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('method_statement.read', project_id));

drop policy if exists method_statements_insert on public.method_statements;
create policy method_statements_insert on public.method_statements
  for insert to authenticated
  with check (public.has_project_permission('method_statement.create', project_id));

drop policy if exists method_statements_update on public.method_statements;
create policy method_statements_update on public.method_statements
  for update to authenticated
  using (
    public.has_project_permission('method_statement.update', project_id)
    or public.has_project_permission('method_statement.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists inspection_requests_select on public.inspection_requests;
create policy inspection_requests_select on public.inspection_requests
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('inspection.read', project_id));

drop policy if exists inspection_requests_insert on public.inspection_requests;
create policy inspection_requests_insert on public.inspection_requests
  for insert to authenticated
  with check (public.has_project_permission('inspection.create', project_id));

drop policy if exists inspection_requests_update on public.inspection_requests;
create policy inspection_requests_update on public.inspection_requests
  for update to authenticated
  using (
    public.has_project_permission('inspection.perform', project_id)
    or public.has_project_permission('inspection.close', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists ncrs_select on public.ncrs;
create policy ncrs_select on public.ncrs
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('ncr.read', project_id));

drop policy if exists ncrs_insert on public.ncrs;
create policy ncrs_insert on public.ncrs
  for insert to authenticated
  with check (public.has_project_permission('ncr.create', project_id));

drop policy if exists ncrs_update on public.ncrs;
create policy ncrs_update on public.ncrs
  for update to authenticated
  using (
    public.has_project_permission('ncr.manage', project_id)
    or public.has_project_permission('ncr.close', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists project_reports_select on public.project_reports;
create policy project_reports_select on public.project_reports
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('report.read', project_id));

drop policy if exists project_reports_insert on public.project_reports;
create policy project_reports_insert on public.project_reports
  for insert to authenticated
  with check (public.has_project_permission('report.create', project_id));

drop policy if exists project_reports_update on public.project_reports;
create policy project_reports_update on public.project_reports
  for update to authenticated
  using (
    public.has_project_permission('report.create', project_id)
    or public.has_project_permission('report.approve', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists correspondence_select on public.correspondence;
create policy correspondence_select on public.correspondence
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('correspondence.read', project_id));

drop policy if exists correspondence_insert on public.correspondence;
create policy correspondence_insert on public.correspondence
  for insert to authenticated
  with check (public.has_project_permission('correspondence.create', project_id));

drop policy if exists correspondence_update on public.correspondence;
create policy correspondence_update on public.correspondence
  for update to authenticated
  using (public.has_project_permission('correspondence.manage', project_id))
  with check (public.can_access_project(project_id));

drop policy if exists project_contacts_select on public.project_contacts;
create policy project_contacts_select on public.project_contacts
  for select to authenticated
  using (public.can_access_project(project_id));

drop policy if exists project_contacts_write on public.project_contacts;
create policy project_contacts_write on public.project_contacts
  for all to authenticated
  using (public.has_project_permission('project.update', project_id)
    or public.has_project_permission('correspondence.manage', project_id))
  with check (public.has_project_permission('project.update', project_id)
    or public.has_project_permission('correspondence.manage', project_id));

drop policy if exists transmittals_select on public.transmittals;
create policy transmittals_select on public.transmittals
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('transmittal.read', project_id));

drop policy if exists transmittals_insert on public.transmittals;
create policy transmittals_insert on public.transmittals
  for insert to authenticated
  with check (public.has_project_permission('transmittal.create', project_id));

drop policy if exists transmittals_update on public.transmittals;
create policy transmittals_update on public.transmittals
  for update to authenticated
  using (
    public.has_project_permission('transmittal.create', project_id)
    or public.has_project_permission('transmittal.issue', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists transmittal_items_select on public.transmittal_items;
create policy transmittal_items_select on public.transmittal_items
  for select to authenticated
  using (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and public.can_access_project(t.project_id)
      and public.has_project_permission('transmittal.read', t.project_id)
  ));

drop policy if exists transmittal_items_write on public.transmittal_items;
create policy transmittal_items_write on public.transmittal_items
  for all to authenticated
  using (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and t.status = 'draft'
      and public.has_project_permission('transmittal.create', t.project_id)
  ))
  with check (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and t.status = 'draft'
      and public.has_project_permission('transmittal.create', t.project_id)
  ));
