-- Master Touch OS — 017
-- RFI (Request for Information) module.

create type public.rfi_status as enum (
  'draft',
  'internal_review',
  'submitted',
  'under_review',
  'answered',
  'closed',
  'cancelled'
);

create type public.rfi_priority as enum ('low', 'medium', 'high', 'critical');
create type public.rfi_impact_type as enum (
  'none',
  'schedule',
  'cost',
  'schedule_and_cost',
  'quality',
  'other'
);

create table public.rfis (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  rfi_number text not null,
  subject text not null,
  question text not null,
  drawing_references text,
  specification_references text,
  location text,
  raised_by uuid not null references public.profiles (id),
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  priority public.rfi_priority not null default 'medium',
  impact_type public.rfi_impact_type not null default 'none',
  potential_schedule_impact boolean not null default false,
  potential_cost_impact boolean not null default false,
  date_raised date not null default (timezone('utc', now()))::date,
  response_required_by timestamptz,
  submitted_to text,
  status public.rfi_status not null default 'draft',
  response text,
  responded_by uuid references public.profiles (id) on delete set null,
  response_date timestamptz,
  related_stage_id uuid references public.project_stages (id) on delete set null,
  related_document_id uuid references public.documents (id) on delete set null,
  related_ncr_id uuid,
  closed_at timestamptz,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, rfi_number)
);

create trigger rfis_set_updated_at
  before update on public.rfis
  for each row execute function public.set_updated_at();

create index rfis_project_idx on public.rfis (project_id, status);
create index rfis_due_idx on public.rfis (response_required_by, status);
create index rfis_discipline_idx on public.rfis (discipline_id);
create index rfis_responsible_idx on public.rfis (responsible_engineer_id);

-- Prevent silent mutation of closed RFIs (question/response integrity)
create or replace function public.protect_closed_rfi()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('closed', 'cancelled') and new.status = old.status then
    if old.question is distinct from new.question
       or old.subject is distinct from new.subject
       or (old.response is not null and old.response is distinct from new.response) then
      raise exception 'CONFLICT';
    end if;
  end if;
  return new;
end;
$$;

create trigger rfis_protect_closed
  before update on public.rfis
  for each row execute function public.protect_closed_rfi();
