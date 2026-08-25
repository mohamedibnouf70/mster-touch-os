-- Master Touch OS — 041
-- Variations / Change Orders (VO).

create type public.variation_status as enum (
  'draft',
  'under_review',
  'submitted',
  'negotiation',
  'approved',
  'partially_approved',
  'rejected',
  'cancelled'
);

create table public.variations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  contract_id uuid references public.project_contracts (id) on delete set null,
  vo_number text not null,
  source text,
  description text not null,
  reason text,
  requested_by uuid references public.profiles (id) on delete set null,
  cost_impact numeric(18, 2) not null default 0,
  time_impact_days integer not null default 0,
  submitted_amount numeric(18, 2) not null default 0,
  approved_amount numeric(18, 2),
  status public.variation_status not null default 'draft',
  submitted_date date,
  approval_date date,
  attachment_document_id uuid references public.documents (id) on delete set null,
  related_rfi_id uuid references public.rfis (id) on delete set null,
  related_ncr_id uuid references public.ncrs (id) on delete set null,
  related_correspondence_id uuid references public.correspondence (id) on delete set null,
  approval_request_id uuid references public.approval_requests (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, vo_number)
);

create trigger variations_set_updated_at
  before update on public.variations
  for each row execute function public.set_updated_at();

create index variations_project_idx on public.variations (project_id, status);

create table public.approval_threshold_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  process_type text not null,
  min_amount numeric(18, 2) not null default 0 check (min_amount >= 0),
  max_amount numeric(18, 2) check (max_amount is null or max_amount >= min_amount),
  required_roles text[] not null default '{}',
  workflow_code text,
  currency text not null default 'SAR',
  is_active boolean not null default true,
  effective_from date not null default (timezone('utc', now()))::date,
  effective_to date,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  check (effective_to is null or effective_to >= effective_from)
);

create index approval_threshold_rules_org_idx
  on public.approval_threshold_rules (organization_id, process_type, is_active);

insert into public.approval_threshold_rules (
  organization_id, process_type, min_amount, max_amount, required_roles, notes
)
select *
from (values
  ('11111111-1111-1111-1111-111111111111'::uuid, 'purchase_order', 0::numeric, 10000::numeric,
   array['project_manager', 'procurement_manager']::text[],
   'PLACEHOLDER: 0–10,000 SAR — confirm with admin'),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'purchase_order', 10000.01::numeric, 50000::numeric,
   array['procurement_manager', 'finance_manager']::text[],
   'PLACEHOLDER: 10,001–50,000 SAR — confirm with admin'),
  ('11111111-1111-1111-1111-111111111111'::uuid, 'purchase_order', 50000.01::numeric, null::numeric,
   array['general_manager', 'finance_manager']::text[],
   'PLACEHOLDER: above 50,000 SAR — confirm with admin')
) as v(organization_id, process_type, min_amount, max_amount, required_roles, notes)
where not exists (
  select 1 from public.approval_threshold_rules r
  where r.organization_id = v.organization_id
    and r.process_type = v.process_type
    and r.min_amount = v.min_amount
);
