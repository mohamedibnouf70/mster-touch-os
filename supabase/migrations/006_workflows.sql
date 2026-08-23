-- Master Touch OS — 006
-- Versioned workflow engine.

create table public.workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  entity_type text not null,
  status public.workflow_definition_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger workflow_definitions_set_updated_at
  before update on public.workflow_definitions
  for each row execute function public.set_updated_at();

create table public.workflow_versions (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references public.workflow_definitions (id) on delete cascade,
  version_number integer not null,
  status public.workflow_definition_status not null default 'draft',
  published_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  unique (definition_id, version_number)
);

create table public.workflow_steps (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.workflow_versions (id) on delete cascade,
  key text not null,
  name_ar text not null,
  name_en text not null,
  sequence integer not null,
  assignee_type public.assignee_type not null default 'unassigned',
  assigned_role_id uuid references public.roles (id) on delete set null,
  assigned_department_id uuid references public.departments (id) on delete set null,
  assigned_user_id uuid references public.profiles (id) on delete set null,
  requires_approval boolean not null default false,
  sla_hours integer,
  warning_hours integer,
  on_reject_step_key text,
  on_resubmit_step_key text,
  is_conditional boolean not null default false,
  unique (version_id, key),
  unique (version_id, sequence)
);

create table public.workflow_step_rules (
  id uuid primary key default gen_random_uuid(),
  step_id uuid not null references public.workflow_steps (id) on delete cascade,
  rule_type text not null,
  condition_json jsonb not null default '{}'::jsonb,
  action_json jsonb not null default '{}'::jsonb
);

create table public.workflow_instances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  definition_id uuid not null references public.workflow_definitions (id),
  version_id uuid not null references public.workflow_versions (id),
  entity_type text not null,
  entity_id uuid not null,
  status public.workflow_instance_status not null default 'pending',
  started_by uuid not null references public.profiles (id),
  started_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger workflow_instances_set_updated_at
  before update on public.workflow_instances
  for each row execute function public.set_updated_at();

create unique index workflow_instances_active_uidx
  on public.workflow_instances (organization_id, entity_type, entity_id, definition_id)
  where status in ('pending', 'in_progress');

create index workflow_instances_entity_idx on public.workflow_instances (entity_type, entity_id);
create index workflow_instances_status_idx on public.workflow_instances (organization_id, status);

create table public.workflow_instance_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  instance_id uuid not null references public.workflow_instances (id) on delete cascade,
  step_id uuid not null references public.workflow_steps (id),
  step_key text not null,
  sequence integer not null,
  status public.workflow_step_status not null default 'pending',
  assigned_user_id uuid references public.profiles (id) on delete set null,
  assigned_role_id uuid references public.roles (id) on delete set null,
  assigned_department_id uuid references public.departments (id) on delete set null,
  due_at timestamptz,
  warning_at timestamptz,
  overdue_at timestamptz,
  escalation_level integer not null default 0,
  escalated_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  completed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger workflow_instance_steps_set_updated_at
  before update on public.workflow_instance_steps
  for each row execute function public.set_updated_at();

create index workflow_instance_steps_instance_idx
  on public.workflow_instance_steps (instance_id, sequence);
create index workflow_instance_steps_assignee_idx
  on public.workflow_instance_steps (assigned_user_id, status);
create index workflow_instance_steps_due_idx
  on public.workflow_instance_steps (due_at, status);
