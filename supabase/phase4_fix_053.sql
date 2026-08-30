-- Master Touch OS — phase4_fix_053
-- Apply this file in the Supabase Dashboard SQL Editor.
-- Equivalent to migrations/053_phase4_contracts_hr_documents.sql
-- Do NOT re-run 001–052. Do NOT modify 001–052.

-- Master Touch OS — 053
-- Phase 4.2: Employee Contracts & Secure HR Documents
-- Additive only. Do not modify 001–052.

-- =============================================================================
-- A. Enums & Types
-- =============================================================================

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'employee_contract_status'
  ) then
    create type public.employee_contract_status as enum (
      'draft',
      'active',
      'expired',
      'renewed',
      'terminated',
      'cancelled'
    );
  end if;
end
$$;

-- =============================================================================
-- B. Employee Contracts
-- =============================================================================

create table if not exists public.employee_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  contract_number text not null,
  contract_type public.employment_type not null default 'permanent',
  status public.employee_contract_status not null default 'draft',
  start_date date not null,
  end_date date,
  probation_end_date date,
  notice_period_days integer not null default 30 check (notice_period_days >= 0),
  working_hours_per_week numeric(5, 2) not null default 40.0 check (working_hours_per_week > 0),
  currency text not null default 'SAR',
  initial_basic_salary numeric(14, 2) check (initial_basic_salary is null or initial_basic_salary >= 0),
  initial_housing_allowance numeric(14, 2) not null default 0 check (initial_housing_allowance >= 0),
  initial_transport_allowance numeric(14, 2) not null default 0 check (initial_transport_allowance >= 0),
  initial_other_allowances numeric(14, 2) not null default 0 check (initial_other_allowances >= 0),
  signed_document_id uuid references public.documents (id) on delete set null,
  is_current boolean not null default false,
  notes text,
  created_by uuid not null references public.profiles (id),
  activated_at timestamptz,
  terminated_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, contract_number),
  check (end_date is null or end_date >= start_date)
);

create trigger employee_contracts_set_updated_at
  before update on public.employee_contracts
  for each row execute function public.set_updated_at();

create index if not exists employee_contracts_emp_idx
  on public.employee_contracts (employee_id, is_current);

create unique index if not exists employee_contracts_current_idx
  on public.employee_contracts (employee_id)
  where (is_current = true);

-- =============================================================================
-- C. Secure HR Documents
-- =============================================================================

create table if not exists public.employee_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  document_id uuid not null references public.documents (id) on delete cascade,
  category text not null check (category in ('contract', 'id', 'iqama', 'passport', 'insurance', 'certificate', 'bank', 'hr_form', 'other')),
  visibility_scope text not null default 'employee_visible' check (visibility_scope in ('hr_only', 'employee_visible', 'finance_visible', 'restricted')),
  document_number text,
  issue_date date,
  expiry_date date,
  notes text,
  uploaded_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (employee_id, document_id)
);

create trigger employee_documents_set_updated_at
  before update on public.employee_documents
  for each row execute function public.set_updated_at();

create index if not exists employee_documents_emp_idx
  on public.employee_documents (employee_id, category);

-- =============================================================================
-- D. Permissions
-- =============================================================================

insert into public.permissions (key, resource, action, description_ar, description_en)
values
  ('employee_contract.read', 'employee_contract', 'read', 'عرض عقود الموظفين', 'Read employee contracts'),
  ('employee_contract.manage', 'employee_contract', 'manage', 'إدارة وتفعيل عقود الموظفين', 'Manage and activate employee contracts'),
  ('employee_document.read', 'employee_document', 'read', 'عرض وثائق الموظفين الخاصة', 'Read secure employee HR documents'),
  ('employee_document.manage', 'employee_document', 'manage', 'إدارة ورفع وثائق الموظفين الخاصة', 'Manage secure employee HR documents')
on conflict (key) do nothing;

-- HR Manager grants
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'hr_manager'
  and r.organization_id is null
  and p.key in (
    'employee_contract.read',
    'employee_contract.manage',
    'employee_document.read',
    'employee_document.manage'
  )
on conflict do nothing;

-- HR Officer grants
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'hr_officer'
  and r.organization_id is null
  and p.key in (
    'employee_contract.read',
    'employee_document.read',
    'employee_document.manage'
  )
on conflict do nothing;

-- Super admin grants
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'super_admin'
  and r.organization_id is null
  and p.key in (
    'employee_contract.read',
    'employee_contract.manage',
    'employee_document.read',
    'employee_document.manage'
  )
on conflict do nothing;

-- =============================================================================
-- E. Helpers & Functions
-- =============================================================================

create or replace function public.can_access_employee_document_row(
  p_employee_id uuid,
  p_organization_id uuid,
  p_category text,
  p_visibility_scope text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin()
    or (
      public.is_organization_member(p_organization_id)
      and (
        -- HR managers can access all documents
        public.has_permission('employee_document.manage', p_organization_id, 'organization', null)
        or public.has_permission('employee.manage', p_organization_id, 'organization', null)
        -- HR officers can access non-restricted documents
        or (
          public.has_permission('employee_document.read', p_organization_id, 'organization', null)
          and p_visibility_scope <> 'restricted'
        )
        -- Employee self-access for allowed scopes
        or (
          exists (
            select 1 from public.employees e
            where e.id = p_employee_id
              and e.organization_id = p_organization_id
              and e.profile_id = auth.uid()
          )
          and p_visibility_scope in ('employee_visible', 'finance_visible')
        )
        -- Finance manager access to banking, contracts, and finance_visible docs
        or (
          (
            public.has_permission('finance.manage', p_organization_id, 'organization', null)
            or public.has_permission('finance.read', p_organization_id, 'organization', null)
          )
          and (p_category in ('bank', 'contract') or p_visibility_scope = 'finance_visible')
        )
      )
    );
$$;

grant execute on function public.can_access_employee_document_row(uuid, uuid, text, text) to authenticated;

-- Contract immutability check
create or replace function public.check_employee_contract_immutability()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (OLD.status in ('active', 'renewed', 'expired', 'terminated')) then
    -- When already active or historical, financial and core contractual terms cannot be altered
    if (
      NEW.start_date <> OLD.start_date
      or NEW.currency <> OLD.currency
      or NEW.initial_basic_salary is distinct from OLD.initial_basic_salary
      or NEW.initial_housing_allowance is distinct from OLD.initial_housing_allowance
      or NEW.initial_transport_allowance is distinct from OLD.initial_transport_allowance
      or NEW.initial_other_allowances is distinct from OLD.initial_other_allowances
      or NEW.contract_number <> OLD.contract_number
      or NEW.employee_id <> OLD.employee_id
      or NEW.organization_id <> OLD.organization_id
    ) then
      raise exception 'IMMUTABLE_CONTRACT: active or historical contract terms cannot be modified directly' using errcode = 'P0001';
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_employee_contract_immutability on public.employee_contracts;
create trigger trg_employee_contract_immutability
  before update on public.employee_contracts
  for each row execute function public.check_employee_contract_immutability();

-- =============================================================================
-- F. Contract Activation RPC
-- =============================================================================

create or replace function public.activate_employee_contract(
  p_organization_id uuid,
  p_contract_id uuid
)
returns public.employee_contracts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contract public.employee_contracts;
  v_emp public.employees;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if not (
    public.has_permission('employee_contract.manage', p_organization_id, 'organization', null)
    or public.has_permission('employee.manage', p_organization_id, 'organization', null)
  ) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  select * into v_contract
  from public.employee_contracts
  where id = p_contract_id and organization_id = p_organization_id
  for update;

  if v_contract.id is null then
    raise exception 'NOT_FOUND: contract not found' using errcode = 'P0001';
  end if;

  select * into v_emp
  from public.employees
  where id = v_contract.employee_id and organization_id = p_organization_id
  for update;

  if v_emp.id is null then
    raise exception 'NOT_FOUND: employee not found' using errcode = 'P0001';
  end if;

  -- Archive / mark previous current contracts as renewed/superseded
  update public.employee_contracts
  set is_current = false,
      status = case when status = 'active' then 'renewed'::public.employee_contract_status else status end,
      updated_at = timezone('utc', now())
  where employee_id = v_contract.employee_id
    and id <> v_contract.id
    and is_current = true;

  -- Activate the target contract
  update public.employee_contracts
  set is_current = true,
      status = 'active',
      activated_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = v_contract.id
  returning * into v_contract;

  -- Update employee snapshot fields
  update public.employees
  set contract_start = v_contract.start_date,
      contract_end = v_contract.end_date,
      probation_end = coalesce(v_contract.probation_end_date, probation_end),
      employment_type = v_contract.contract_type,
      updated_at = timezone('utc', now())
  where id = v_emp.id;

  -- Sync HR alert hooks for contract & probation dates
  perform public.sync_employee_hr_alert_hooks(v_emp.id);

  -- Audit & domain event
  perform public.log_audit(
    p_organization_id,
    'employee_contract.activated',
    'employee_contract',
    v_contract.id,
    null,
    jsonb_build_object(
      'employee_id', v_contract.employee_id,
      'contract_number', v_contract.contract_number,
      'contract_type', v_contract.contract_type,
      'start_date', v_contract.start_date,
      'end_date', v_contract.end_date
    )
  );

  return v_contract;
end;
$$;

grant execute on function public.activate_employee_contract(uuid, uuid) to authenticated;

-- =============================================================================
-- G. Row Level Security (RLS)
-- =============================================================================

alter table public.employee_contracts enable row level security;
alter table public.employee_documents enable row level security;

-- Contracts RLS
drop policy if exists employee_contracts_select on public.employee_contracts;
create policy employee_contracts_select on public.employee_contracts
  for select to authenticated
  using (
    public.is_platform_admin()
    or (
      public.is_organization_member(organization_id)
      and (
        public.has_permission('employee_contract.read', organization_id, 'organization', null)
        or public.has_permission('employee_contract.manage', organization_id, 'organization', null)
        or public.has_permission('employee.manage', organization_id, 'organization', null)
        -- Self read active/current contract
        or (
          exists (
            select 1 from public.employees e
            where e.id = employee_id
              and e.organization_id = organization_id
              and e.profile_id = auth.uid()
          )
        )
      )
    )
  );

drop policy if exists employee_contracts_insert on public.employee_contracts;
create policy employee_contracts_insert on public.employee_contracts
  for insert to authenticated
  with check (
    public.has_permission('employee_contract.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_contracts_update on public.employee_contracts;
create policy employee_contracts_update on public.employee_contracts
  for update to authenticated
  using (
    public.has_permission('employee_contract.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  )
  with check (
    public.has_permission('employee_contract.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_contracts_delete on public.employee_contracts;
create policy employee_contracts_delete on public.employee_contracts
  for delete to authenticated
  using (false);

-- Employee Documents RLS
drop policy if exists employee_documents_select on public.employee_documents;
create policy employee_documents_select on public.employee_documents
  for select to authenticated
  using (
    public.can_access_employee_document_row(employee_id, organization_id, category, visibility_scope)
  );

drop policy if exists employee_documents_insert on public.employee_documents;
create policy employee_documents_insert on public.employee_documents
  for insert to authenticated
  with check (
    public.has_permission('employee_document.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_documents_update on public.employee_documents;
create policy employee_documents_update on public.employee_documents
  for update to authenticated
  using (
    public.has_permission('employee_document.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  )
  with check (
    public.has_permission('employee_document.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_documents_delete on public.employee_documents;
create policy employee_documents_delete on public.employee_documents
  for delete to authenticated
  using (
    public.has_permission('employee_document.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

-- Allow reading linked documents in public.documents & document_versions for HR documents
drop policy if exists documents_select_hr on public.documents;
create policy documents_select_hr on public.documents
  for select to authenticated
  using (
    exists (
      select 1 from public.employee_documents ed
      where ed.document_id = id
        and public.can_access_employee_document_row(ed.employee_id, ed.organization_id, ed.category, ed.visibility_scope)
    )
  );

drop policy if exists document_versions_select_hr on public.document_versions;
create policy document_versions_select_hr on public.document_versions
  for select to authenticated
  using (
    exists (
      select 1 from public.employee_documents ed
      where ed.document_id = document_id
        and public.can_access_employee_document_row(ed.employee_id, ed.organization_id, ed.category, ed.visibility_scope)
    )
  );
