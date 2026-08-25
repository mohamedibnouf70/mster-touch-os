-- Master Touch OS — 035
-- Supplier quotations + commercial comparison / recommendation.

create type public.quotation_status as enum (
  'draft',
  'submitted',
  'under_review',
  'accepted',
  'rejected',
  'expired',
  'superseded'
);

create type public.compliance_status as enum (
  'compliant',
  'partial',
  'non_compliant',
  'not_assessed'
);

create table public.supplier_quotations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  rfq_id uuid not null references public.rfqs (id) on delete restrict,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  quotation_number text not null,
  quotation_date date not null default (timezone('utc', now()))::date,
  validity_date date,
  currency text not null default 'SAR',
  subtotal numeric(18, 2) not null default 0 check (subtotal >= 0),
  discount numeric(18, 2) not null default 0 check (discount >= 0),
  vat_rate_percent numeric(6, 3) not null default 0 check (vat_rate_percent >= 0),
  vat_amount numeric(18, 2) not null default 0 check (vat_amount >= 0),
  total numeric(18, 2) not null default 0 check (total >= 0),
  delivery_lead_time_days integer check (delivery_lead_time_days is null or delivery_lead_time_days >= 0),
  payment_terms text,
  warranty text,
  attachment_document_id uuid references public.documents (id) on delete set null,
  commercial_notes text,
  technical_compliance public.compliance_status not null default 'not_assessed',
  status public.quotation_status not null default 'draft',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, quotation_number),
  unique (rfq_id, supplier_id, quotation_number)
);

create trigger supplier_quotations_set_updated_at
  before update on public.supplier_quotations
  for each row execute function public.set_updated_at();

create index supplier_quotations_rfq_idx on public.supplier_quotations (rfq_id, status);
create index supplier_quotations_supplier_idx on public.supplier_quotations (supplier_id);

create table public.supplier_quotation_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  quotation_id uuid not null references public.supplier_quotations (id) on delete cascade,
  rfq_item_id uuid references public.rfq_items (id) on delete set null,
  line_no integer not null default 1,
  description text not null,
  quantity numeric(18, 4) not null check (quantity > 0),
  unit text,
  unit_price numeric(18, 4) not null default 0 check (unit_price >= 0),
  total_price numeric(18, 2) not null default 0 check (total_price >= 0),
  offered_brand text,
  offered_model text,
  lead_time_days integer,
  compliance_status public.compliance_status not null default 'not_assessed',
  deviation_note text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (quotation_id, line_no)
);

create table public.quotation_comparisons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  rfq_id uuid not null unique references public.rfqs (id) on delete cascade,
  recommended_supplier_id uuid references public.suppliers (id) on delete set null,
  recommended_quotation_id uuid references public.supplier_quotations (id) on delete set null,
  recommendation_reason text,
  recommended_by uuid references public.profiles (id) on delete set null,
  recommended_at timestamptz,
  approval_request_id uuid references public.approval_requests (id) on delete set null,
  status text not null default 'open'
    check (status in ('open', 'recommended', 'pending_approval', 'awarded', 'cancelled')),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger quotation_comparisons_set_updated_at
  before update on public.quotation_comparisons
  for each row execute function public.set_updated_at();
