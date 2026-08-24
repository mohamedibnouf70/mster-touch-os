-- Master Touch OS — 020
-- Method Statements.

create type public.method_statement_status as enum (
  'draft',
  'internal_review',
  'hse_review',
  'quality_review',
  'pm_review',
  'ready_for_submission',
  'submitted',
  'under_review',
  'approved',
  'approved_as_noted',
  'resubmit',
  'rejected',
  'approved_for_use',
  'superseded',
  'closed'
);

create table public.method_statements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  ms_number text not null,
  activity text not null,
  scope text,
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  method_procedure text,
  required_manpower text,
  equipment_tools text,
  materials text,
  safety_requirements text,
  quality_requirements text,
  inspection_testing_requirements text,
  references_text text,
  requires_hse_review boolean not null default true,
  requires_quality_review boolean not null default true,
  status public.method_statement_status not null default 'draft',
  official_decision text check (official_decision is null or official_decision in ('A', 'B', 'C', 'D', 'E')),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, ms_number)
);

create trigger method_statements_set_updated_at
  before update on public.method_statements
  for each row execute function public.set_updated_at();

create index method_statements_project_idx on public.method_statements (project_id, status);
