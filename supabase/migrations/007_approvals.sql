-- Master Touch OS — 007
-- Generic approval engine with official A–E outcomes.

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  title text not null,
  status public.approval_request_status not null default 'pending',
  mode public.approval_mode not null default 'sequential',
  official_outcome public.approval_decision not null default 'pending',
  official_code text,
  requested_by uuid not null references public.profiles (id),
  due_at timestamptz,
  warning_at timestamptz,
  overdue_at timestamptz,
  escalation_level integer not null default 0,
  escalated_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (official_code is null or official_code in ('A', 'B', 'C', 'D', 'E'))
);

create trigger approval_requests_set_updated_at
  before update on public.approval_requests
  for each row execute function public.set_updated_at();

create index approval_requests_entity_idx on public.approval_requests (entity_type, entity_id);
create index approval_requests_status_idx on public.approval_requests (organization_id, status);
create index approval_requests_due_idx on public.approval_requests (due_at, status);

create table public.approval_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  request_id uuid not null references public.approval_requests (id) on delete cascade,
  sequence integer not null,
  approver_type public.approver_type not null,
  role_id uuid references public.roles (id) on delete set null,
  department_id uuid references public.departments (id) on delete set null,
  user_id uuid references public.profiles (id) on delete set null,
  delegated_to uuid references public.profiles (id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'in_progress', 'completed', 'skipped', 'cancelled')),
  due_at timestamptz,
  warning_at timestamptz,
  overdue_at timestamptz,
  escalation_level integer not null default 0,
  escalated_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (request_id, sequence)
);

create trigger approval_steps_set_updated_at
  before update on public.approval_steps
  for each row execute function public.set_updated_at();

create index approval_steps_assignee_idx on public.approval_steps (user_id, status);
create index approval_steps_due_idx on public.approval_steps (due_at, status);

create table public.approval_actions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  request_id uuid not null references public.approval_requests (id) on delete cascade,
  step_id uuid not null references public.approval_steps (id) on delete cascade,
  actor_id uuid not null references public.profiles (id),
  decision public.approval_decision not null,
  official_code text not null check (official_code in ('A', 'B', 'C', 'D', 'E')),
  comment text,
  attachment_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create unique index approval_actions_step_once_uidx
  on public.approval_actions (step_id);

create index approval_actions_request_idx on public.approval_actions (request_id, created_at);
