-- Master Touch OS — 003
-- Identity, membership, departments, and employee foundation.
-- Auth identity stays in auth.users. Business data lives here.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name_ar text not null default '',
  full_name_en text not null default '',
  phone text,
  locale text not null default 'ar' check (locale in ('ar', 'en')),
  is_active boolean not null default true,
  is_platform_admin boolean not null default false,
  avatar_path text,
  last_seen_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  status public.membership_status not null default 'active',
  joined_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, profile_id)
);

create trigger organization_members_set_updated_at
  before update on public.organization_members
  for each row execute function public.set_updated_at();

create index organization_members_profile_idx on public.organization_members (profile_id, status);
create index organization_members_org_idx on public.organization_members (organization_id, status);

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  description text,
  parent_department_id uuid references public.departments (id) on delete set null,
  manager_user_id uuid references public.profiles (id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create trigger departments_set_updated_at
  before update on public.departments
  for each row execute function public.set_updated_at();

create index departments_org_idx on public.departments (organization_id, is_active);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  employee_number text,
  job_title_ar text,
  job_title_en text,
  employment_status public.employment_status not null default 'active',
  joining_date date,
  contract_start date,
  contract_end date,
  probation_end date,
  direct_manager_employee_id uuid references public.employees (id) on delete set null,
  work_location text,
  nationality text,
  is_active boolean not null default true,
  terminated_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, profile_id),
  unique (organization_id, employee_number)
);

create trigger employees_set_updated_at
  before update on public.employees
  for each row execute function public.set_updated_at();

create index employees_org_status_idx on public.employees (organization_id, is_active, employment_status);
create index employees_manager_idx on public.employees (direct_manager_employee_id);

create table public.employee_departments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  department_id uuid not null references public.departments (id) on delete cascade,
  is_primary boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  unique (employee_id, department_id)
);

create index employee_departments_dept_idx on public.employee_departments (department_id);

create table public.employee_compliance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null unique references public.employees (id) on delete cascade,
  iqama_number text,
  iqama_expiry date,
  passport_number text,
  passport_expiry date,
  work_permit_expiry date,
  insurance_provider text,
  insurance_expiry date,
  gosi_number text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger employee_compliance_set_updated_at
  before update on public.employee_compliance
  for each row execute function public.set_updated_at();

create index employee_compliance_expiry_idx on public.employee_compliance (
  iqama_expiry,
  passport_expiry,
  work_permit_expiry,
  insurance_expiry
);

-- Restricted compensation table. No salary UI in Phase 1.
create table public.employee_compensation (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null unique references public.employees (id) on delete cascade,
  basic_salary numeric(14, 2),
  housing_allowance numeric(14, 2),
  transport_allowance numeric(14, 2),
  other_allowances numeric(14, 2),
  currency text not null default 'SAR',
  payroll_cycle text,
  next_payroll_date date,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger employee_compensation_set_updated_at
  before update on public.employee_compensation
  for each row execute function public.set_updated_at();

create table public.hr_alert_hooks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  alert_type text not null,
  due_date date not null,
  warning_date date,
  status text not null default 'scheduled',
  created_at timestamptz not null default timezone('utc', now()),
  unique (employee_id, alert_type, due_date)
);

create index hr_alert_hooks_due_idx on public.hr_alert_hooks (organization_id, due_date, status);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name_ar, full_name_en, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name_ar', new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'full_name_en', new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'locale', 'ar')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
