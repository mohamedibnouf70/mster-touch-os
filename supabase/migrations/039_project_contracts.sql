-- Master Touch OS — 039
-- Project contracts + payment milestones.

create type public.contract_status as enum (
  'draft',
  'active',
  'suspended',
  'completed',
  'terminated',
  'archived'
);

create type public.milestone_status as enum (
  'planned',
  'eligible',
  'claimed',
  'approved',
  'invoiced',
  'paid',
  'partially_paid'
);

create table public.project_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  client_name text not null,
  contract_number text not null,
  contract_date date,
  contract_value numeric(18, 2) not null check (contract_value >= 0),
  currency text not null default 'SAR',
  vat_amount numeric(18, 2) not null default 0 check (vat_amount >= 0),
  retention_percent numeric(6, 3) not null default 0 check (retention_percent >= 0 and retention_percent <= 100),
  advance_payment_percent numeric(6, 3) not null default 0 check (advance_payment_percent >= 0 and advance_payment_percent <= 100),
  start_date date,
  planned_completion date,
  payment_terms text,
  delay_penalty_terms text,
  variation_rules text,
  attachment_document_id uuid references public.documents (id) on delete set null,
  status public.contract_status not null default 'draft',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, contract_number)
);

create trigger project_contracts_set_updated_at
  before update on public.project_contracts
  for each row execute function public.set_updated_at();

create index project_contracts_project_idx on public.project_contracts (project_id, status);

-- Protect original contract_value from silent overwrite once active
create or replace function public.protect_active_contract_value()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return new;
  end if;
  if old.status in ('active', 'completed') and new.contract_value is distinct from old.contract_value then
    raise exception 'Original contract value is immutable; use variations'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger project_contracts_protect_value
  before update on public.project_contracts
  for each row execute function public.protect_active_contract_value();

create table public.contract_milestones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  contract_id uuid not null references public.project_contracts (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  milestone_number integer not null,
  description text not null,
  percentage numeric(6, 3) check (percentage is null or (percentage >= 0 and percentage <= 100)),
  amount numeric(18, 2) not null check (amount >= 0),
  trigger_event text,
  planned_date date,
  actual_eligible_date date,
  status public.milestone_status not null default 'planned',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (contract_id, milestone_number)
);

create trigger contract_milestones_set_updated_at
  before update on public.contract_milestones
  for each row execute function public.set_updated_at();

create index contract_milestones_project_idx on public.contract_milestones (project_id, status);
