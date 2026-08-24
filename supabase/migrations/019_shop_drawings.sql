-- Master Touch OS — 019
-- Shop Drawings.

create type public.shop_drawing_status as enum (
  'draft',
  'internal_review',
  'ready_for_submission',
  'submitted',
  'under_review',
  'approved',
  'approved_as_noted',
  'resubmit',
  'rejected',
  'superseded',
  'closed'
);

create table public.shop_drawings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  shd_number text not null,
  drawing_title text not null,
  drawing_number text,
  related_design_drawing text,
  floor_zone_location text,
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  prepared_by uuid references public.profiles (id) on delete set null,
  checked_by uuid references public.profiles (id) on delete set null,
  submission_date date,
  status public.shop_drawing_status not null default 'draft',
  official_decision text check (official_decision is null or official_decision in ('A', 'B', 'C', 'D', 'E')),
  approval_comments text,
  approved_for_execution boolean not null default false,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, shd_number)
);

create trigger shop_drawings_set_updated_at
  before update on public.shop_drawings
  for each row execute function public.set_updated_at();

create index shop_drawings_project_idx on public.shop_drawings (project_id, status);
create index shop_drawings_afe_idx on public.shop_drawings (project_id, approved_for_execution)
  where approved_for_execution = true;

-- Only A/B current revisions may be marked approved for execution
create or replace function public.enforce_shop_drawing_afe()
returns trigger
language plpgsql
as $$
begin
  if new.approved_for_execution = true then
    if new.official_decision is distinct from 'A' and new.official_decision is distinct from 'B' then
      raise exception 'VALIDATION';
    end if;
    if new.status in ('resubmit', 'rejected', 'superseded', 'draft') then
      raise exception 'VALIDATION';
    end if;
  end if;
  return new;
end;
$$;

create trigger shop_drawings_enforce_afe
  before insert or update on public.shop_drawings
  for each row execute function public.enforce_shop_drawing_afe();
