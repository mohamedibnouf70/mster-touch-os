-- Master Touch OS — 038
-- Supplier invoices + payments + match flags.

create type public.supplier_invoice_status as enum (
  'received',
  'under_review',
  'matched',
  'discrepancy',
  'approved_for_payment',
  'partially_paid',
  'paid',
  'rejected',
  'cancelled'
);

create type public.payment_method as enum (
  'bank_transfer',
  'cheque',
  'cash',
  'card',
  'other'
);

create table public.supplier_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  purchase_order_id uuid references public.purchase_orders (id) on delete set null,
  invoice_number text not null,
  invoice_date date not null,
  due_date date,
  currency text not null default 'SAR',
  subtotal numeric(18, 2) not null default 0 check (subtotal >= 0),
  vat_amount numeric(18, 2) not null default 0 check (vat_amount >= 0),
  total numeric(18, 2) not null default 0 check (total >= 0),
  attachment_document_id uuid references public.documents (id) on delete set null,
  status public.supplier_invoice_status not null default 'received',
  review_notes text,
  match_flags jsonb not null default '[]'::jsonb,
  created_by uuid not null references public.profiles (id),
  reviewed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, supplier_id, invoice_number),
  check (due_date is null or due_date >= invoice_date)
);

create trigger supplier_invoices_set_updated_at
  before update on public.supplier_invoices
  for each row execute function public.set_updated_at();

create index supplier_invoices_due_idx on public.supplier_invoices (due_date, status);
create index supplier_invoices_project_idx on public.supplier_invoices (project_id, status);

create table public.supplier_invoice_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  supplier_invoice_id uuid not null references public.supplier_invoices (id) on delete cascade,
  purchase_order_item_id uuid references public.purchase_order_items (id) on delete set null,
  description text not null,
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_price numeric(18, 4) not null default 0,
  line_total numeric(18, 2) not null default 0,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  supplier_invoice_id uuid not null references public.supplier_invoices (id) on delete restrict,
  payment_reference text not null,
  amount numeric(18, 2) not null check (amount > 0),
  payment_date date not null,
  payment_method public.payment_method not null default 'bank_transfer',
  bank_reference text,
  notes text,
  attachment_document_id uuid references public.documents (id) on delete set null,
  recorded_by uuid not null references public.profiles (id),
  approved_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, payment_reference)
);

create index supplier_payments_invoice_idx on public.supplier_payments (supplier_invoice_id);
create index supplier_payments_project_idx on public.supplier_payments (project_id);
