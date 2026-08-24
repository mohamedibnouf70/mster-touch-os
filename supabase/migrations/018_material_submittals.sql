-- Master Touch OS — 018
-- Material Submittals.

create type public.submittal_status as enum (
  'draft',
  'internal_review',
  'ready_for_submission',
  'submitted',
  'under_review',
  'approved',
  'approved_as_noted',
  'resubmit',
  'rejected',
  'for_information',
  'superseded',
  'closed'
);

create table public.material_submittals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  mat_number text not null,
  material_category text not null,
  manufacturer text,
  supplier text,
  model text,
  country_of_origin text,
  specification_section text,
  boq_reference text,
  proposed_use_location text,
  technical_description text,
  samples_required boolean not null default false,
  sample_status text,
  submitted_by uuid references public.profiles (id) on delete set null,
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  submission_date date,
  required_approval_date date,
  consultant_client text,
  status public.submittal_status not null default 'draft',
  official_decision text check (official_decision is null or official_decision in ('A', 'B', 'C', 'D', 'E')),
  review_comments text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, mat_number)
);

create trigger material_submittals_set_updated_at
  before update on public.material_submittals
  for each row execute function public.set_updated_at();

create index material_submittals_project_idx on public.material_submittals (project_id, status);
create index material_submittals_decision_idx on public.material_submittals (official_decision);
create index material_submittals_due_idx on public.material_submittals (required_approval_date, status);
