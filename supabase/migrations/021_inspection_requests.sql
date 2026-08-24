-- Master Touch OS — 021
-- Inspection Requests.

create type public.inspection_status as enum (
  'draft',
  'ready',
  'submitted',
  'scheduled',
  'inspected',
  'passed',
  'passed_with_comments',
  'failed',
  'reinspection_required',
  'closed'
);

create table public.inspection_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  ir_number text not null,
  related_activity text,
  location text,
  related_drawing_id uuid references public.documents (id) on delete set null,
  related_method_statement_id uuid references public.method_statements (id) on delete set null,
  related_material_submittal_id uuid references public.material_submittals (id) on delete set null,
  inspection_date_requested date,
  requested_by uuid references public.profiles (id) on delete set null,
  site_engineer_id uuid references public.profiles (id) on delete set null,
  quality_engineer_id uuid references public.profiles (id) on delete set null,
  consultant_inspector text,
  checklist jsonb not null default '[]'::jsonb,
  inspection_result text,
  comments text,
  status public.inspection_status not null default 'draft',
  parent_inspection_id uuid references public.inspection_requests (id) on delete set null,
  related_ncr_id uuid,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, ir_number)
);

create trigger inspection_requests_set_updated_at
  before update on public.inspection_requests
  for each row execute function public.set_updated_at();

create index inspection_requests_project_idx on public.inspection_requests (project_id, status);
create index inspection_requests_parent_idx on public.inspection_requests (parent_inspection_id);
