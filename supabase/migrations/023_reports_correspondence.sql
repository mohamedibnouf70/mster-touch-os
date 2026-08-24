-- Master Touch OS — 023
-- Project reports and formal correspondence register.

create type public.project_report_type as enum ('daily', 'weekly', 'monthly');

create type public.project_report_status as enum (
  'draft',
  'submitted',
  'approved',
  'archived'
);

create table public.project_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid references public.documents (id) on delete set null,
  report_type public.project_report_type not null,
  report_number text,
  period_start date not null,
  period_end date not null,
  prepared_by uuid not null references public.profiles (id),
  weather_site_condition text,
  manpower jsonb not null default '{}'::jsonb,
  activities_completed text,
  activities_in_progress text,
  planned_activities text,
  delays text,
  issues text,
  risks text,
  materials_received text,
  inspections_summary text,
  safety_observations text,
  notes text,
  management_summary text,
  status public.project_report_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (period_end >= period_start)
);

create trigger project_reports_set_updated_at
  before update on public.project_reports
  for each row execute function public.set_updated_at();

create index project_reports_project_idx on public.project_reports (project_id, report_type, period_start desc);

create type public.correspondence_direction as enum ('incoming', 'outgoing', 'internal');

create type public.correspondence_status as enum (
  'open',
  'awaiting_response',
  'responded',
  'closed'
);

create table public.correspondence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid references public.documents (id) on delete set null,
  reference_number text not null,
  direction public.correspondence_direction not null,
  sender text not null,
  recipient text not null,
  cc text,
  subject text not null,
  body_summary text,
  correspondence_date date not null default (timezone('utc', now()))::date,
  response_required boolean not null default false,
  response_due_date date,
  response_received boolean not null default false,
  related_entity_type text,
  related_entity_id uuid,
  status public.correspondence_status not null default 'open',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, reference_number)
);

create trigger correspondence_set_updated_at
  before update on public.correspondence
  for each row execute function public.set_updated_at();

create index correspondence_project_idx on public.correspondence (project_id, status);
create index correspondence_due_idx on public.correspondence (response_due_date, status)
  where response_required = true;
