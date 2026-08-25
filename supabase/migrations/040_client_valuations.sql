-- Master Touch OS — 040
-- Client valuations, invoices, payments.

create type public.valuation_status as enum (
  'draft',
  'internal_review',
  'submitted',
  'under_client_review',
  'certified',
  'partially_certified',
  'rejected',
  'invoiced',
  'paid',
  'closed'
);

create type public.client_invoice_status as enum (
  'draft',
  'issued',
  'partially_paid',
  'paid',
  'overdue',
  'cancelled'
);

create table public.client_valuations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  contract_id uuid not null references public.project_contracts (id) on delete restrict,
  valuation_number text not null,
  period_start date,
  period_end date,
  progress_percentage numeric(6, 3) check (progress_percentage is null or (progress_percentage >= 0 and progress_percentage <= 100)),
  gross_work_value numeric(18, 2) not null default 0,
  variations_amount numeric(18, 2) not null default 0,
  retention_amount numeric(18, 2) not null default 0,
  advance_recovery numeric(18, 2) not null default 0,
  previous_certified_amount numeric(18, 2) not null default 0,
  current_claim_amount numeric(18, 2) not null default 0,
  vat_amount numeric(18, 2) not null default 0,
  total_claim numeric(18, 2) not null default 0,
  submitted_date date,
  due_date date,
  certified_amount numeric(18, 2),
  certification_date date,
  status public.valuation_status not null default 'draft',
  attachment_document_id uuid references public.documents (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, valuation_number),
  check (period_end is null or period_start is null or period_end >= period_start)
);

create trigger client_valuations_set_updated_at
  before update on public.client_valuations
  for each row execute function public.set_updated_at();

create index client_valuations_project_idx on public.client_valuations (project_id, status);

create table public.client_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  contract_id uuid references public.project_contracts (id) on delete set null,
  valuation_id uuid references public.client_valuations (id) on delete set null,
  invoice_number text not null,
  invoice_date date not null,
  due_date date,
  currency text not null default 'SAR',
  amount numeric(18, 2) not null default 0 check (amount >= 0),
  vat_amount numeric(18, 2) not null default 0 check (vat_amount >= 0),
  total numeric(18, 2) not null default 0 check (total >= 0),
  status public.client_invoice_status not null default 'draft',
  attachment_document_id uuid references public.documents (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  issued_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, invoice_number)
);

create trigger client_invoices_set_updated_at
  before update on public.client_invoices
  for each row execute function public.set_updated_at();

create index client_invoices_due_idx on public.client_invoices (due_date, status);
create index client_invoices_project_idx on public.client_invoices (project_id, status);

create table public.client_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  client_invoice_id uuid not null references public.client_invoices (id) on delete restrict,
  amount numeric(18, 2) not null check (amount > 0),
  received_date date not null,
  reference text,
  payment_method public.payment_method not null default 'bank_transfer',
  attachment_document_id uuid references public.documents (id) on delete set null,
  recorded_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now())
);

create index client_payments_invoice_idx on public.client_payments (client_invoice_id);
create index client_payments_project_idx on public.client_payments (project_id);
