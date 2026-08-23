-- Master Touch OS — 005
-- Project core, stages, team assignments, and concurrency-safe codes.

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name_ar text not null,
  name_en text not null,
  status text not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger clients_set_updated_at
  before update on public.clients
  for each row execute function public.set_updated_at();

create index clients_org_idx on public.clients (organization_id);

create table public.project_counters (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  prefix text not null default 'MT-PRJ',
  next_value integer not null default 0
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_code text not null,
  name_ar text not null,
  name_en text not null,
  description text,
  client_id uuid references public.clients (id) on delete set null,
  project_manager_id uuid references public.profiles (id) on delete set null,
  status public.project_status not null default 'draft',
  priority public.project_priority not null default 'medium',
  start_date date,
  planned_end_date date,
  actual_end_date date,
  contract_value numeric(16, 2),
  budget numeric(16, 2),
  progress_percentage numeric(5, 2) not null default 0,
  risk_level public.risk_level not null default 'low',
  location text,
  business_case_document_id uuid,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  archived_at timestamptz,
  unique (organization_id, project_code)
);

create trigger projects_set_updated_at
  before update on public.projects
  for each row execute function public.set_updated_at();

create index projects_org_status_idx on public.projects (organization_id, status);
create index projects_manager_idx on public.projects (project_manager_id);
create index projects_risk_idx on public.projects (organization_id, risk_level);
create index projects_created_idx on public.projects (organization_id, created_at desc);

create table public.project_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  employee_id uuid references public.employees (id) on delete set null,
  role_label text,
  is_active boolean not null default true,
  assigned_at timestamptz not null default timezone('utc', now()),
  unassigned_at timestamptz,
  unique (project_id, profile_id)
);

create index project_members_profile_idx on public.project_members (profile_id, is_active);
create index project_members_project_idx on public.project_members (project_id, is_active);

create table public.employee_project_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  role_title text,
  is_active boolean not null default true,
  assigned_at timestamptz not null default timezone('utc', now()),
  unassigned_at timestamptz,
  unique (employee_id, project_id)
);

create index employee_project_assignments_project_idx
  on public.employee_project_assignments (project_id, is_active);

create table public.project_stage_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger project_stage_templates_set_updated_at
  before update on public.project_stage_templates
  for each row execute function public.set_updated_at();

create table public.project_stage_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.project_stage_templates (id) on delete cascade,
  name_ar text not null,
  name_en text not null,
  sequence integer not null,
  department_code text,
  requires_approval boolean not null default false,
  sla_hours integer,
  risk_level public.risk_level not null default 'low',
  unique (template_id, sequence)
);

create table public.project_stages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  template_item_id uuid references public.project_stage_template_items (id) on delete set null,
  name_ar text not null,
  name_en text not null,
  sequence integer not null,
  owner_user_id uuid references public.profiles (id) on delete set null,
  department_id uuid references public.departments (id) on delete set null,
  planned_start date,
  planned_end date,
  actual_start date,
  actual_end date,
  status public.stage_status not null default 'not_started',
  progress_percentage numeric(5, 2) not null default 0,
  requires_approval boolean not null default false,
  sla_hours integer,
  due_at timestamptz,
  warning_at timestamptz,
  overdue_at timestamptz,
  escalation_level integer not null default 0,
  escalated_at timestamptz,
  risk_level public.risk_level not null default 'low',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (project_id, sequence)
);

create trigger project_stages_set_updated_at
  before update on public.project_stages
  for each row execute function public.set_updated_at();

create index project_stages_project_idx on public.project_stages (project_id, sequence);
create index project_stages_status_idx on public.project_stages (organization_id, status);
create index project_stages_due_idx on public.project_stages (due_at);

create table public.project_stage_dependencies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  stage_id uuid not null references public.project_stages (id) on delete cascade,
  depends_on_stage_id uuid not null references public.project_stages (id) on delete cascade,
  unique (stage_id, depends_on_stage_id),
  check (stage_id <> depends_on_stage_id)
);
