-- Master Touch OS — phase4_fix_054
-- Apply this file in the Supabase Dashboard SQL Editor.
-- Equivalent to migrations/054_phase4_compensation_banking.sql
-- Do NOT re-run 001–053. Do NOT modify 001–053.

-- Master Touch OS — 054
-- Phase 4.2: Versioned Compensation & Employee Banking
-- Additive only. Do not modify 001–053.

-- =============================================================================
-- A. Versioned Compensation Table
-- =============================================================================

create table if not exists public.employee_compensation_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  effective_from date not null,
  effective_to date,
  currency text not null default 'SAR',
  basic_salary numeric(14, 2) not null check (basic_salary >= 0),
  housing_allowance numeric(14, 2) not null default 0 check (housing_allowance >= 0),
  transport_allowance numeric(14, 2) not null default 0 check (transport_allowance >= 0),
  other_allowances numeric(14, 2) not null default 0 check (other_allowances >= 0),
  change_reason text,
  status text not null default 'active' check (status in ('active', 'superseded', 'cancelled')),
  created_by uuid not null references public.profiles (id),
  approved_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (effective_to is null or effective_to >= effective_from)
);

create trigger employee_compensation_versions_set_updated_at
  before update on public.employee_compensation_versions
  for each row execute function public.set_updated_at();

create index if not exists emp_comp_versions_lookup_idx
  on public.employee_compensation_versions (employee_id, effective_from desc);

-- =============================================================================
-- B. Employee Bank Accounts Table
-- =============================================================================

create table if not exists public.employee_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  bank_name text not null,
  iban text not null,
  account_name text not null,
  swift_code text,
  is_primary boolean not null default true,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger employee_bank_accounts_set_updated_at
  before update on public.employee_bank_accounts
  for each row execute function public.set_updated_at();

create index if not exists emp_bank_accounts_emp_idx
  on public.employee_bank_accounts (employee_id, is_active);

-- =============================================================================
-- C. Permissions
-- =============================================================================

insert into public.permissions (key, resource, action, description_ar, description_en)
values
  ('employee_compensation.read', 'employee_compensation', 'read', 'عرض سجل الرواتب والبدلات للموظف', 'Read employee compensation history and versions'),
  ('employee_compensation.manage', 'employee_compensation', 'manage', 'إدارة وتعديل نسخ الرواتب والبدلات', 'Manage and create employee compensation versions'),
  ('employee_bank.read', 'employee_bank', 'read', 'عرض الحسابات البنكية للموظف', 'Read employee banking details'),
  ('employee_bank.manage', 'employee_bank', 'manage', 'إدارة الحسابات البنكية للموظف', 'Manage employee bank accounts')
on conflict (key) do nothing;

-- HR Manager grants
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'hr_manager'
  and r.organization_id is null
  and p.key in (
    'employee_compensation.read',
    'employee_compensation.manage',
    'employee_bank.read',
    'employee_bank.manage'
  )
on conflict do nothing;

-- Finance Manager grants
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'finance_manager'
  and r.organization_id is null
  and p.key in (
    'employee_compensation.read',
    'employee_bank.read',
    'employee_bank.manage'
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
    'employee_compensation.read',
    'employee_compensation.manage',
    'employee_bank.read',
    'employee_bank.manage'
  )
on conflict do nothing;

-- =============================================================================
-- D. Backfill from legacy employee_compensation (if any exist)
-- =============================================================================

insert into public.employee_compensation_versions (
  organization_id,
  employee_id,
  effective_from,
  currency,
  basic_salary,
  housing_allowance,
  transport_allowance,
  other_allowances,
  change_reason,
  status,
  created_by
)
select
  ec.organization_id,
  ec.employee_id,
  coalesce(e.joining_date, e.created_at::date, CURRENT_DATE),
  coalesce(ec.currency, 'SAR'),
  coalesce(ec.basic_salary, 0),
  coalesce(ec.housing_allowance, 0),
  coalesce(ec.transport_allowance, 0),
  coalesce(ec.other_allowances, 0),
  'Initial backfill from legacy compensation',
  'active',
  e.profile_id
from public.employee_compensation ec
join public.employees e on e.id = ec.employee_id
where ec.basic_salary is not null
  and ec.basic_salary > 0
  and not exists (
    select 1 from public.employee_compensation_versions v
    where v.employee_id = ec.employee_id
  );

-- =============================================================================
-- E. Compensation Versioning RPC & Immutability Trigger
-- =============================================================================

create or replace function public.check_employee_compensation_version_immutability()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (OLD.status = 'superseded' and NEW.status = 'superseded') then
    if (
      NEW.basic_salary <> OLD.basic_salary
      or NEW.housing_allowance <> OLD.housing_allowance
      or NEW.transport_allowance <> OLD.transport_allowance
      or NEW.other_allowances <> OLD.other_allowances
      or NEW.effective_from <> OLD.effective_from
      or NEW.effective_to <> OLD.effective_to
      or NEW.currency <> OLD.currency
    ) then
      raise exception 'IMMUTABLE_COMPENSATION: superseded compensation versions cannot be modified' using errcode = 'P0001';
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_employee_compensation_version_immutability on public.employee_compensation_versions;
create trigger trg_employee_compensation_version_immutability
  before update on public.employee_compensation_versions
  for each row execute function public.check_employee_compensation_version_immutability();

create or replace function public.create_employee_compensation_version(
  p_organization_id uuid,
  p_employee_id uuid,
  p_effective_from date,
  p_currency text,
  p_basic_salary numeric,
  p_housing_allowance numeric default 0,
  p_transport_allowance numeric default 0,
  p_other_allowances numeric default 0,
  p_change_reason text default null
)
returns public.employee_compensation_versions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version public.employee_compensation_versions;
  v_emp public.employees;
  v_overlap boolean;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if not (
    public.has_permission('employee_compensation.manage', p_organization_id, 'organization', null)
    or public.has_permission('employee.manage', p_organization_id, 'organization', null)
  ) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if p_effective_from is null then
    raise exception 'VALIDATION: effective_from is required' using errcode = 'P0001';
  end if;

  if coalesce(p_basic_salary, 0) < 0 or coalesce(p_housing_allowance, 0) < 0
     or coalesce(p_transport_allowance, 0) < 0 or coalesce(p_other_allowances, 0) < 0 then
    raise exception 'VALIDATION: salary and allowance values cannot be negative' using errcode = 'P0001';
  end if;

  select * into v_emp
  from public.employees
  where id = p_employee_id and organization_id = p_organization_id
  for update;

  if v_emp.id is null then
    raise exception 'NOT_FOUND: employee not found' using errcode = 'P0001';
  end if;

  -- Lock active versions for concurrency
  perform 1
  from public.employee_compensation_versions
  where employee_id = p_employee_id and organization_id = p_organization_id
  for update;

  -- Close prior open-ended active versions that start before this new version
  update public.employee_compensation_versions
  set effective_to = (p_effective_from - 1),
      status = 'superseded',
      updated_at = timezone('utc', now())
  where employee_id = p_employee_id
    and organization_id = p_organization_id
    and effective_to is null
    and effective_from < p_effective_from
    and status = 'active';

  -- Check for overlap with existing active ranges
  select exists (
    select 1
    from public.employee_compensation_versions
    where employee_id = p_employee_id
      and organization_id = p_organization_id
      and status = 'active'
      and daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') &&
          daterange(p_effective_from, 'infinity'::date, '[]')
  ) into v_overlap;

  if v_overlap then
    raise exception 'OVERLAPPING_COMPENSATION_RANGE: effective date range conflicts with an existing active version' using errcode = 'P0001';
  end if;

  -- Insert the new compensation version
  insert into public.employee_compensation_versions (
    organization_id,
    employee_id,
    effective_from,
    effective_to,
    currency,
    basic_salary,
    housing_allowance,
    transport_allowance,
    other_allowances,
    change_reason,
    status,
    created_by
  ) values (
    p_organization_id,
    p_employee_id,
    p_effective_from,
    null,
    coalesce(trim(p_currency), 'SAR'),
    p_basic_salary,
    coalesce(p_housing_allowance, 0),
    coalesce(p_transport_allowance, 0),
    coalesce(p_other_allowances, 0),
    trim(p_change_reason),
    'active',
    auth.uid()
  )
  returning * into v_version;

  -- Update legacy table row for backward compatibility
  insert into public.employee_compensation (
    organization_id,
    employee_id,
    basic_salary,
    housing_allowance,
    transport_allowance,
    other_allowances,
    currency,
    updated_at
  ) values (
    p_organization_id,
    p_employee_id,
    v_version.basic_salary,
    v_version.housing_allowance,
    v_version.transport_allowance,
    v_version.other_allowances,
    v_version.currency,
    timezone('utc', now())
  )
  on conflict (employee_id) do update
  set basic_salary = excluded.basic_salary,
      housing_allowance = excluded.housing_allowance,
      transport_allowance = excluded.transport_allowance,
      other_allowances = excluded.other_allowances,
      currency = excluded.currency,
      updated_at = timezone('utc', now());

  -- Audit log (omitting raw salary amount for privacy)
  perform public.log_audit(
    p_organization_id,
    'employee_compensation.changed',
    'employee',
    p_employee_id,
    null,
    jsonb_build_object(
      'version_id', v_version.id,
      'effective_from', v_version.effective_from,
      'currency', v_version.currency
    )
  );

  return v_version;
end;
$$;

grant execute on function public.create_employee_compensation_version(
  uuid, uuid, date, text, numeric, numeric, numeric, numeric, text
) to authenticated;

-- =============================================================================
-- F. Employee Banking RPCs
-- =============================================================================

create or replace function public.get_employee_banking(
  p_employee_id uuid
)
returns table (
  id uuid,
  organization_id uuid,
  employee_id uuid,
  bank_name text,
  iban text,
  masked_iban text,
  account_name text,
  swift_code text,
  is_primary boolean,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
  v_is_self boolean;
  v_can_manage boolean;
  v_can_read boolean;
begin
  select * into v_emp from public.employees where id = p_employee_id;
  if v_emp.id is null then
    return;
  end if;

  if not public.is_organization_member(v_emp.organization_id) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  v_is_self := (v_emp.profile_id = auth.uid());
  v_can_manage := public.has_permission('employee_bank.manage', v_emp.organization_id, 'organization', null)
               or public.has_permission('finance.manage', v_emp.organization_id, 'organization', null)
               or public.has_permission('employee.manage', v_emp.organization_id, 'organization', null);
  v_can_read := public.has_permission('employee_bank.read', v_emp.organization_id, 'organization', null)
             or public.has_permission('finance.read', v_emp.organization_id, 'organization', null);

  if not (public.is_platform_admin() or v_can_manage or v_can_read or v_is_self) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  return query
  select
    b.id,
    b.organization_id,
    b.employee_id,
    b.bank_name,
    case
      when public.is_platform_admin() or v_can_manage or v_can_read then b.iban
      else null::text
    end as iban,
    case
      when length(b.iban) >= 8 then
        substr(b.iban, 1, 4) || ' **** **** **** ' || substr(b.iban, length(b.iban) - 3, 4)
      else '****'
    end as masked_iban,
    b.account_name,
    b.swift_code,
    b.is_primary,
    b.is_active,
    b.created_at,
    b.updated_at
  from public.employee_bank_accounts b
  where b.employee_id = p_employee_id
    and b.organization_id = v_emp.organization_id
  order by b.is_primary desc, b.created_at desc;
end;
$$;

grant execute on function public.get_employee_banking(uuid) to authenticated;

create or replace function public.upsert_employee_banking(
  p_organization_id uuid,
  p_employee_id uuid,
  p_bank_name text,
  p_iban text,
  p_account_name text,
  p_swift_code text default null,
  p_is_primary boolean default true,
  p_account_id uuid default null
)
returns public.employee_bank_accounts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
  v_row public.employee_bank_accounts;
  v_clean_iban text;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if not (
    public.has_permission('employee_bank.manage', p_organization_id, 'organization', null)
    or public.has_permission('finance.manage', p_organization_id, 'organization', null)
    or public.has_permission('employee.manage', p_organization_id, 'organization', null)
  ) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  select * into v_emp
  from public.employees
  where id = p_employee_id and organization_id = p_organization_id;

  if v_emp.id is null then
    raise exception 'NOT_FOUND: employee not found' using errcode = 'P0001';
  end if;

  v_clean_iban := upper(replace(trim(p_iban), ' ', ''));
  if length(v_clean_iban) < 15 then
    raise exception 'VALIDATION: invalid IBAN length' using errcode = 'P0001';
  end if;

  if coalesce(trim(p_bank_name), '') = '' or coalesce(trim(p_account_name), '') = '' then
    raise exception 'VALIDATION: bank name and account name are required' using errcode = 'P0001';
  end if;

  if p_is_primary then
    update public.employee_bank_accounts
    set is_primary = false,
        updated_at = timezone('utc', now())
    where employee_id = p_employee_id
      and organization_id = p_organization_id
      and is_primary = true;
  end if;

  if p_account_id is null then
    insert into public.employee_bank_accounts (
      organization_id,
      employee_id,
      bank_name,
      iban,
      account_name,
      swift_code,
      is_primary,
      is_active,
      created_by
    ) values (
      p_organization_id,
      p_employee_id,
      trim(p_bank_name),
      v_clean_iban,
      trim(p_account_name),
      nullif(trim(coalesce(p_swift_code, '')), ''),
      coalesce(p_is_primary, true),
      true,
      auth.uid()
    )
    returning * into v_row;
  else
    update public.employee_bank_accounts
    set bank_name = trim(p_bank_name),
        iban = v_clean_iban,
        account_name = trim(p_account_name),
        swift_code = nullif(trim(coalesce(p_swift_code, '')), ''),
        is_primary = coalesce(p_is_primary, is_primary),
        is_active = true,
        updated_at = timezone('utc', now())
    where id = p_account_id
      and organization_id = p_organization_id
      and employee_id = p_employee_id
    returning * into v_row;

    if v_row.id is null then
      raise exception 'NOT_FOUND: bank account not found' using errcode = 'P0001';
    end if;
  end if;

  perform public.log_audit(
    p_organization_id,
    'employee_bank.updated',
    'employee',
    p_employee_id,
    null,
    jsonb_build_object(
      'bank_name', v_row.bank_name,
      'is_primary', v_row.is_primary,
      'account_id', v_row.id
    )
  );

  return v_row;
end;
$$;

grant execute on function public.upsert_employee_banking(
  uuid, uuid, text, text, text, text, boolean, uuid
) to authenticated;

create or replace function public.deactivate_employee_bank_account(
  p_organization_id uuid,
  p_account_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.employee_bank_accounts;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if not (
    public.has_permission('employee_bank.manage', p_organization_id, 'organization', null)
    or public.has_permission('finance.manage', p_organization_id, 'organization', null)
    or public.has_permission('employee.manage', p_organization_id, 'organization', null)
  ) then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  update public.employee_bank_accounts
  set is_active = false,
      is_primary = false,
      updated_at = timezone('utc', now())
  where id = p_account_id
    and organization_id = p_organization_id
  returning * into v_row;

  if v_row.id is null then
    raise exception 'NOT_FOUND: bank account not found' using errcode = 'P0001';
  end if;

  perform public.log_audit(
    p_organization_id,
    'employee_bank.deactivated',
    'employee',
    v_row.employee_id,
    null,
    jsonb_build_object(
      'account_id', v_row.id,
      'bank_name', v_row.bank_name
    )
  );
end;
$$;

grant execute on function public.deactivate_employee_bank_account(uuid, uuid) to authenticated;

-- =============================================================================
-- G. Row Level Security (RLS)
-- =============================================================================

alter table public.employee_compensation_versions enable row level security;
alter table public.employee_bank_accounts enable row level security;

-- Compensation versions RLS
drop policy if exists employee_compensation_versions_select on public.employee_compensation_versions;
create policy employee_compensation_versions_select on public.employee_compensation_versions
  for select to authenticated
  using (
    public.is_platform_admin()
    or (
      public.is_organization_member(organization_id)
      and (
        public.has_permission('employee_compensation.read', organization_id, 'organization', null)
        or public.has_permission('employee_compensation.manage', organization_id, 'organization', null)
        or public.has_permission('finance.read', organization_id, 'organization', null)
        or public.has_permission('finance.manage', organization_id, 'organization', null)
        or public.has_permission('employee.manage', organization_id, 'organization', null)
      )
    )
  );

drop policy if exists employee_compensation_versions_insert on public.employee_compensation_versions;
create policy employee_compensation_versions_insert on public.employee_compensation_versions
  for insert to authenticated
  with check (
    public.has_permission('employee_compensation.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_compensation_versions_update on public.employee_compensation_versions;
create policy employee_compensation_versions_update on public.employee_compensation_versions
  for update to authenticated
  using (
    public.has_permission('employee_compensation.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  )
  with check (
    public.has_permission('employee_compensation.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_compensation_versions_delete on public.employee_compensation_versions;
create policy employee_compensation_versions_delete on public.employee_compensation_versions
  for delete to authenticated
  using (false);

-- Bank Accounts RLS
drop policy if exists employee_bank_accounts_select on public.employee_bank_accounts;
create policy employee_bank_accounts_select on public.employee_bank_accounts
  for select to authenticated
  using (
    public.is_platform_admin()
    or (
      public.is_organization_member(organization_id)
      and (
        public.has_permission('employee_bank.read', organization_id, 'organization', null)
        or public.has_permission('employee_bank.manage', organization_id, 'organization', null)
        or public.has_permission('finance.read', organization_id, 'organization', null)
        or public.has_permission('finance.manage', organization_id, 'organization', null)
        or public.has_permission('employee.manage', organization_id, 'organization', null)
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

drop policy if exists employee_bank_accounts_insert on public.employee_bank_accounts;
create policy employee_bank_accounts_insert on public.employee_bank_accounts
  for insert to authenticated
  with check (
    public.has_permission('employee_bank.manage', organization_id, 'organization', null)
    or public.has_permission('finance.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_bank_accounts_update on public.employee_bank_accounts;
create policy employee_bank_accounts_update on public.employee_bank_accounts
  for update to authenticated
  using (
    public.has_permission('employee_bank.manage', organization_id, 'organization', null)
    or public.has_permission('finance.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  )
  with check (
    public.has_permission('employee_bank.manage', organization_id, 'organization', null)
    or public.has_permission('finance.manage', organization_id, 'organization', null)
    or public.has_permission('employee.manage', organization_id, 'organization', null)
  );

drop policy if exists employee_bank_accounts_delete on public.employee_bank_accounts;
create policy employee_bank_accounts_delete on public.employee_bank_accounts
  for delete to authenticated
  using (false);
