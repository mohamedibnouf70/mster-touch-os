-- Master Touch OS — 022
-- NCR (Non-Conformance Reports).

create type public.ncr_severity as enum ('low', 'medium', 'high', 'critical');

create type public.ncr_status as enum (
  'open',
  'under_investigation',
  'corrective_action',
  'waiting_verification',
  'closed',
  'reopened'
);

create table public.ncrs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  ncr_number text not null,
  location text,
  reported_by uuid not null references public.profiles (id),
  assigned_to uuid references public.profiles (id) on delete set null,
  severity public.ncr_severity not null default 'medium',
  description text not null,
  requirement_violated text,
  evidence_notes text,
  root_cause text,
  corrective_action text,
  preventive_action text,
  responsible_person_id uuid references public.profiles (id) on delete set null,
  target_closure_date date,
  actual_closure_date date,
  verification text,
  verified_by uuid references public.profiles (id) on delete set null,
  verified_at timestamptz,
  status public.ncr_status not null default 'open',
  related_inspection_id uuid references public.inspection_requests (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, ncr_number),
  check (
    status <> 'closed'
    or (verification is not null and verified_by is not null)
  )
);

create trigger ncrs_set_updated_at
  before update on public.ncrs
  for each row execute function public.set_updated_at();

create index ncrs_project_idx on public.ncrs (project_id, status);
create index ncrs_severity_idx on public.ncrs (severity, status);
create index ncrs_due_idx on public.ncrs (target_closure_date, status);

-- Backfill FKs from RFI / IR that reference NCR
alter table public.rfis
  add constraint rfis_related_ncr_fk
  foreign key (related_ncr_id) references public.ncrs (id) on delete set null;

alter table public.inspection_requests
  add constraint inspection_requests_related_ncr_fk
  foreign key (related_ncr_id) references public.ncrs (id) on delete set null;
