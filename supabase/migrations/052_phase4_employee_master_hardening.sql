-- Master Touch OS — 052
-- Phase 4.1: Employee master data + organization structure hardening.
-- Additive only. Do not modify 001–051.
--
-- Adds:
-- 1) Optional DOB / gender / employment_type on employees
-- 2) HR permissions (employee.create, compliance, alerts, sensitive)
-- 3) Compliance self-read RLS; alert-hook write policies
-- 4) Department manager scoped directory helper (no compensation access)
-- 5) Department hierarchy validation RPC
-- 6) HR alert-hook upsert helper for Phase 4.1 date fields

-- =============================================================================
-- A. Employees — optional master-data columns
-- =============================================================================

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'employment_type'
  ) then
    create type public.employment_type as enum (
      'permanent',
      'fixed_term',
      'part_time',
      'temporary',
      'consultant'
    );
  end if;
end
$$;

alter table public.employees
  add column if not exists date_of_birth date;

alter table public.employees
  add column if not exists gender text;

alter table public.employees
  drop constraint if exists employees_gender_check;

alter table public.employees
  add constraint employees_gender_check
  check (gender is null or gender in ('male', 'female', 'other', 'unspecified'));

alter table public.employees
  add column if not exists employment_type public.employment_type;

comment on column public.employees.date_of_birth is
  'Optional. HR/self scoped in application projections.';
comment on column public.employees.gender is
  'Optional. male|female|other|unspecified. Never required for account creation.';
comment on column public.employees.employment_type is
  'Optional employment classification. Labels resolved in application catalog.';

-- =============================================================================
-- B. Permissions
-- =============================================================================

insert into public.permissions (key, resource, action, description_ar, description_en)
values
  ('employee.create', 'employee', 'create', 'إنشاء موظف / حساب دخول محدود', 'Create employee / limited login account'),
  ('employee.read_sensitive', 'employee', 'read_sensitive', 'قراءة حقول موظف حساسة (غير الراتب)', 'Read sensitive non-compensation employee fields'),
  ('employee_compliance.read', 'employee_compliance', 'read', 'قراءة بيانات الامتثال للموظفين', 'Read employee compliance records'),
  ('employee_compliance.manage', 'employee_compliance', 'manage', 'إدارة بيانات الامتثال للموظفين', 'Manage employee compliance records'),
  ('hr_alert.read', 'hr_alert', 'read', 'قراءة تنبيهات الموارد البشرية', 'Read HR alert hooks'),
  ('hr_alert.manage', 'hr_alert', 'manage', 'إدارة تنبيهات الموارد البشرية', 'Manage HR alert hooks')
on conflict (key) do nothing;

-- HR Manager — full Phase 4.1 HR operational set (not user.create / role.assign)
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'hr_manager'
  and r.organization_id is null
  and p.key in (
    'employee.create',
    'employee.read',
    'employee.manage',
    'employee.read_sensitive',
    'employee_compliance.read',
    'employee_compliance.manage',
    'hr_alert.read',
    'hr_alert.manage',
    'department.create',
    'department.read',
    'department.update',
    'user.read',
    'user.update',
    'notification.read',
    'audit.read'
  )
on conflict do nothing;

-- HR Officer — read + compliance read; no create/manage/user admin
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'hr_officer'
  and r.organization_id is null
  and p.key in (
    'employee.read',
    'employee_compliance.read',
    'hr_alert.read',
    'department.read',
    'user.read',
    'notification.read'
  )
on conflict do nothing;

-- Department manager: remove org-wide employee.read; rely on scoped helper below.
delete from public.role_permissions rp
using public.roles r
where rp.role_id = r.id
  and r.code = 'department_manager'
  and r.organization_id is null
  and rp.permission_key = 'employee.read';

-- =============================================================================
-- C. Helpers — department manager scope (directory only; never compensation)
-- =============================================================================

create or replace function public.is_department_manager_of_employee(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.employee_departments ed
    join public.departments d on d.id = ed.department_id
    join public.employees e on e.id = ed.employee_id
    where ed.employee_id = p_employee_id
      and d.manager_user_id = auth.uid()
      and d.is_active = true
      and d.organization_id = e.organization_id
      and public.is_organization_member(d.organization_id)
  );
$$;

grant execute on function public.is_department_manager_of_employee(uuid) to authenticated;

create or replace function public.can_read_employee_row(p_employee_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_organization_member(p_organization_id)
    and (
      exists (
        select 1 from public.employees e
        where e.id = p_employee_id
          and e.organization_id = p_organization_id
          and e.profile_id = auth.uid()
      )
      or public.has_permission('employee.read', p_organization_id, 'organization', null)
      or public.has_permission('employee.manage', p_organization_id, 'organization', null)
      or public.is_department_manager_of_employee(p_employee_id)
    );
$$;

grant execute on function public.can_read_employee_row(uuid, uuid) to authenticated;

comment on function public.is_department_manager_of_employee(uuid) is
  'True when auth.uid() manages an active department containing the employee. Does not grant compensation/payroll/bank access.';

-- =============================================================================
-- D. RLS — employees / compliance / alerts
-- =============================================================================

drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees
  for select to authenticated
  using (public.can_read_employee_row(id, organization_id));

drop policy if exists employees_write on public.employees;
drop policy if exists employees_insert on public.employees;
drop policy if exists employees_update on public.employees;
drop policy if exists employees_delete on public.employees;

-- Note: onboard via Auth Admin API still uses service-role for auth.users creation.
-- employee.create gates the application action; authenticated insert allowed for completeness.
create policy employees_insert on public.employees
  for insert to authenticated
  with check (
    public.has_permission('employee.manage', organization_id, 'organization', null)
    or public.has_permission('employee.create', organization_id, 'organization', null)
  );

create policy employees_update on public.employees
  for update to authenticated
  using (public.has_permission('employee.manage', organization_id, 'organization', null))
  with check (public.has_permission('employee.manage', organization_id, 'organization', null));

create policy employees_delete on public.employees
  for delete to authenticated
  using (false);

drop policy if exists employee_compliance_select on public.employee_compliance;
create policy employee_compliance_select on public.employee_compliance
  for select to authenticated
  using (
    exists (
      select 1 from public.employees e
      where e.id = employee_id
        and e.organization_id = organization_id
        and e.profile_id = auth.uid()
    )
    or public.has_permission('employee_compliance.read', organization_id, 'organization', null)
    or public.has_permission('employee_compliance.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_compliance_write on public.employee_compliance;
create policy employee_compliance_write on public.employee_compliance
  for all to authenticated
  using (
    public.has_permission('employee_compliance.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  )
  with check (
    public.has_permission('employee_compliance.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists hr_alert_hooks_select on public.hr_alert_hooks;
create policy hr_alert_hooks_select on public.hr_alert_hooks
  for select to authenticated
  using (
    public.has_permission('hr_alert.read', organization_id, 'organization', null)
    or public.has_permission('hr_alert.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists hr_alert_hooks_write on public.hr_alert_hooks;
create policy hr_alert_hooks_write on public.hr_alert_hooks
  for all to authenticated
  using (
    public.has_permission('hr_alert.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  )
  with check (
    public.has_permission('hr_alert.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

-- Compensation stays finance.manage OR employee.manage — never department manager / employee.read.
-- (policy employee_compensation_all unchanged intentionally)

-- =============================================================================
-- E. Department hierarchy validation
-- =============================================================================

create or replace function public.department_would_create_cycle(
  p_department_id uuid,
  p_parent_department_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_walk uuid := p_parent_department_id;
  v_guard int := 0;
begin
  if p_parent_department_id is null then
    return false;
  end if;
  if p_department_id is not null and p_parent_department_id = p_department_id then
    return true;
  end if;

  while v_walk is not null loop
    if p_department_id is not null and v_walk = p_department_id then
      return true;
    end if;
    select parent_department_id into v_walk
    from public.departments
    where id = v_walk;
    v_guard := v_guard + 1;
    if v_guard > 50 then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

grant execute on function public.department_would_create_cycle(uuid, uuid) to authenticated;

create or replace function public.upsert_department(
  p_organization_id uuid,
  p_department_id uuid,
  p_code text,
  p_name_ar text,
  p_name_en text,
  p_description text,
  p_parent_department_id uuid,
  p_manager_user_id uuid,
  p_is_active boolean default true
)
returns public.departments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.departments;
  v_parent public.departments;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if p_department_id is null then
    if not public.has_permission('department.create', p_organization_id, 'organization', null) then
      raise exception 'FORBIDDEN' using errcode = 'P0001';
    end if;
  else
    if not public.has_permission('department.update', p_organization_id, 'organization', null) then
      raise exception 'FORBIDDEN' using errcode = 'P0001';
    end if;
  end if;

  if coalesce(trim(p_code), '') = '' or coalesce(trim(p_name_ar), '') = '' or coalesce(trim(p_name_en), '') = '' then
    raise exception 'VALIDATION: department code and names are required' using errcode = 'P0001';
  end if;

  if public.department_would_create_cycle(p_department_id, p_parent_department_id) then
    raise exception 'DEPARTMENT_CYCLE: parent would create a circular hierarchy' using errcode = 'P0001';
  end if;

  if p_parent_department_id is not null then
    select * into v_parent from public.departments where id = p_parent_department_id;
    if v_parent.id is null or v_parent.organization_id <> p_organization_id then
      raise exception 'VALIDATION: parent department must belong to the same organization' using errcode = 'P0001';
    end if;
  end if;

  if p_manager_user_id is not null then
    if not exists (
      select 1 from public.organization_members om
      where om.organization_id = p_organization_id
        and om.profile_id = p_manager_user_id
        and om.status = 'active'
    ) then
      raise exception 'VALIDATION: manager must be an active organization member' using errcode = 'P0001';
    end if;
  end if;

  if p_department_id is null then
    insert into public.departments (
      organization_id, code, name_ar, name_en, description,
      parent_department_id, manager_user_id, is_active
    ) values (
      p_organization_id, trim(p_code), trim(p_name_ar), trim(p_name_en), nullif(trim(coalesce(p_description, '')), ''),
      p_parent_department_id, p_manager_user_id, coalesce(p_is_active, true)
    )
    returning * into v_row;
  else
    update public.departments
    set code = trim(p_code),
        name_ar = trim(p_name_ar),
        name_en = trim(p_name_en),
        description = nullif(trim(coalesce(p_description, '')), ''),
        parent_department_id = p_parent_department_id,
        manager_user_id = p_manager_user_id,
        is_active = coalesce(p_is_active, true),
        updated_at = timezone('utc', now())
    where id = p_department_id
      and organization_id = p_organization_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'NOT_FOUND' using errcode = 'P0001';
    end if;
  end if;

  perform public.log_audit(
    p_organization_id,
    case when p_department_id is null then 'department.created' else 'department.updated' end,
    'department',
    v_row.id,
    null,
    jsonb_build_object('code', v_row.code, 'name_ar', v_row.name_ar, 'is_active', v_row.is_active)
  );

  return v_row;
end;
$$;

grant execute on function public.upsert_department(
  uuid, uuid, text, text, text, text, uuid, uuid, boolean
) to authenticated;

-- =============================================================================
-- F. HR alert-hook upsert (no cron; structured preparation only)
-- =============================================================================

create or replace function public.upsert_hr_alert_hook(
  p_organization_id uuid,
  p_employee_id uuid,
  p_alert_type text,
  p_due_date date,
  p_warning_days int default 30
)
returns public.hr_alert_hooks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.hr_alert_hooks;
begin
  if p_due_date is null or coalesce(trim(p_alert_type), '') = '' then
    raise exception 'VALIDATION' using errcode = 'P0001';
  end if;

  if not (
    public.has_permission('hr_alert.manage', p_organization_id, 'organization', null)
    or public.has_permission('employee.manage', p_organization_id, 'organization', null)
  ) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  insert into public.hr_alert_hooks (
    organization_id, employee_id, alert_type, due_date, warning_date, status
  ) values (
    p_organization_id,
    p_employee_id,
    trim(p_alert_type),
    p_due_date,
    (p_due_date - make_interval(days => greatest(coalesce(p_warning_days, 30), 1)))::date,
    'scheduled'
  )
  on conflict (employee_id, alert_type, due_date) do update
    set warning_date = excluded.warning_date,
        status = case
          when hr_alert_hooks.status in ('dismissed', 'completed') then hr_alert_hooks.status
          else 'scheduled'
        end
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.upsert_hr_alert_hook(uuid, uuid, text, date, int) to authenticated;

create or replace function public.sync_employee_hr_alert_hooks(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
  v_comp public.employee_compliance;
begin
  select * into v_emp from public.employees where id = p_employee_id;
  if v_emp.id is null then
    return;
  end if;

  if not (
    public.has_permission('hr_alert.manage', v_emp.organization_id, 'organization', null)
    or public.has_permission('employee.manage', v_emp.organization_id, 'organization', null)
  ) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if v_emp.probation_end is not null then
    perform public.upsert_hr_alert_hook(v_emp.organization_id, v_emp.id, 'probation_end', v_emp.probation_end, 14);
  end if;
  if v_emp.contract_end is not null then
    perform public.upsert_hr_alert_hook(v_emp.organization_id, v_emp.id, 'contract_end', v_emp.contract_end, 30);
  end if;

  select * into v_comp from public.employee_compliance where employee_id = p_employee_id;
  if v_comp.id is not null then
    if v_comp.iqama_expiry is not null then
      perform public.upsert_hr_alert_hook(v_emp.organization_id, v_emp.id, 'iqama_expiry', v_comp.iqama_expiry, 60);
    end if;
    if v_comp.passport_expiry is not null then
      perform public.upsert_hr_alert_hook(v_emp.organization_id, v_emp.id, 'passport_expiry', v_comp.passport_expiry, 90);
    end if;
    if v_comp.work_permit_expiry is not null then
      perform public.upsert_hr_alert_hook(v_emp.organization_id, v_emp.id, 'work_permit_expiry', v_comp.work_permit_expiry, 60);
    end if;
    if v_comp.insurance_expiry is not null then
      perform public.upsert_hr_alert_hook(v_emp.organization_id, v_emp.id, 'insurance_expiry', v_comp.insurance_expiry, 30);
    end if;
  end if;
end;
$$;

grant execute on function public.sync_employee_hr_alert_hooks(uuid) to authenticated;

comment on function public.sync_employee_hr_alert_hooks(uuid) is
  'Upserts scheduled hr_alert_hooks for Phase 4.1 employment/compliance dates. No notifications/cron.';
