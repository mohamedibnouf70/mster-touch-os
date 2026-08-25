-- Master Touch OS — 033
-- Purchase Requests (PR) + items.

create type public.purchase_request_status as enum (
  'draft',
  'submitted',
  'under_review',
  'approved',
  'rejected',
  'cancelled',
  'converted_to_rfq'
);

create type public.pr_priority as enum ('low', 'medium', 'high', 'critical');

create table public.commercial_number_counters (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  doc_type text not null,
  next_value integer not null default 1,
  primary key (organization_id, project_id, doc_type)
);

create table public.purchase_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  pr_number text not null,
  requested_by uuid not null references public.profiles (id),
  department_id uuid references public.departments (id) on delete set null,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  required_date date,
  priority public.pr_priority not null default 'medium',
  justification text,
  budget_item_id uuid references public.project_budget_items (id) on delete set null,
  estimated_cost numeric(18, 2) check (estimated_cost is null or estimated_cost >= 0),
  currency text not null default 'SAR',
  status public.purchase_request_status not null default 'draft',
  approval_request_id uuid references public.approval_requests (id) on delete set null,
  document_id uuid references public.documents (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  submitted_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, pr_number)
);

create trigger purchase_requests_set_updated_at
  before update on public.purchase_requests
  for each row execute function public.set_updated_at();

create index purchase_requests_project_idx on public.purchase_requests (project_id, status);
create index purchase_requests_due_idx on public.purchase_requests (required_date, status);

create table public.purchase_request_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_request_id uuid not null references public.purchase_requests (id) on delete cascade,
  line_no integer not null default 1,
  description text not null,
  specification text,
  quantity numeric(18, 4) not null check (quantity > 0),
  unit text,
  preferred_supplier_id uuid references public.suppliers (id) on delete set null,
  required_delivery_date date,
  estimated_unit_cost numeric(18, 4) check (estimated_unit_cost is null or estimated_unit_cost >= 0),
  estimated_total numeric(18, 2) check (estimated_total is null or estimated_total >= 0),
  related_material_submittal_id uuid references public.material_submittals (id) on delete set null,
  related_document_id uuid references public.documents (id) on delete set null,
  budget_item_id uuid references public.project_budget_items (id) on delete set null,
  project_stage_id uuid references public.project_stages (id) on delete set null,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (purchase_request_id, line_no)
);

create index purchase_request_items_pr_idx on public.purchase_request_items (purchase_request_id);
