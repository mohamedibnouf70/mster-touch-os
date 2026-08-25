-- Master Touch OS — 034
-- RFQ + items + supplier invitations.

create type public.rfq_status as enum (
  'draft',
  'ready_to_issue',
  'issued',
  'responses_received',
  'under_comparison',
  'awarded',
  'cancelled',
  'closed'
);

create type public.rfq_supplier_response_status as enum (
  'invited',
  'acknowledged',
  'responded',
  'declined',
  'no_response'
);

create table public.rfqs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  purchase_request_id uuid references public.purchase_requests (id) on delete set null,
  rfq_number text not null,
  title text not null,
  description text,
  issue_date date,
  response_due_date date,
  responsible_officer_id uuid references public.profiles (id) on delete set null,
  status public.rfq_status not null default 'draft',
  commercial_notes text,
  issued_at timestamptz,
  issued_by uuid references public.profiles (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, rfq_number),
  check (response_due_date is null or issue_date is null or response_due_date >= issue_date)
);

create trigger rfqs_set_updated_at
  before update on public.rfqs
  for each row execute function public.set_updated_at();

create index rfqs_project_idx on public.rfqs (project_id, status);
create index rfqs_due_idx on public.rfqs (response_due_date, status);

create table public.rfq_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  rfq_id uuid not null references public.rfqs (id) on delete cascade,
  purchase_request_item_id uuid references public.purchase_request_items (id) on delete set null,
  line_no integer not null default 1,
  description text not null,
  specification text,
  quantity numeric(18, 4) not null check (quantity > 0),
  unit text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (rfq_id, line_no)
);

create table public.rfq_suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  rfq_id uuid not null references public.rfqs (id) on delete cascade,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  invited_at timestamptz not null default timezone('utc', now()),
  sent_by uuid references public.profiles (id) on delete set null,
  response_status public.rfq_supplier_response_status not null default 'invited',
  responded_at timestamptz,
  decline_reason text,
  unique (rfq_id, supplier_id)
);

create index rfq_suppliers_rfq_idx on public.rfq_suppliers (rfq_id, response_status);
