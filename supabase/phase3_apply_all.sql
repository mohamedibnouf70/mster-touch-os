-- Master Touch OS — Phase 3 apply (031–045)
-- Apply in Supabase SQL Editor after Phase 2 (030) is applied.
-- Verify first: supabase/phase2_verify.sql (extend for Phase 3 tables)


-- ===== 031_suppliers.sql =====

-- Master Touch OS — 031
-- Suppliers, categories, contacts, concurrency-safe supplier codes.

create type public.supplier_status as enum (
  'active',
  'suspended',
  'blocked',
  'archived'
);

create table public.supplier_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create trigger supplier_categories_set_updated_at
  before update on public.supplier_categories
  for each row execute function public.set_updated_at();

create table public.supplier_counters (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  next_value integer not null default 1
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  supplier_code text not null,
  legal_name text not null,
  trade_name text,
  category_id uuid references public.supplier_categories (id) on delete set null,
  commercial_registration text,
  vat_number text,
  country text not null default 'SA',
  city text,
  address text,
  email text,
  phone text,
  whatsapp_phone text,
  website text,
  contact_person text,
  payment_terms_days integer not null default 30 check (payment_terms_days >= 0),
  default_currency text not null default 'SAR',
  bank_name text,
  iban text,
  status public.supplier_status not null default 'active',
  rating numeric(3, 2) check (rating is null or (rating >= 0 and rating <= 5)),
  notes text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  archived_at timestamptz,
  unique (organization_id, supplier_code)
);

create trigger suppliers_set_updated_at
  before update on public.suppliers
  for each row execute function public.set_updated_at();

create index suppliers_org_status_idx on public.suppliers (organization_id, status);
create index suppliers_category_idx on public.suppliers (category_id);
create index suppliers_name_idx on public.suppliers (organization_id, legal_name);

create table public.supplier_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  supplier_id uuid not null references public.suppliers (id) on delete cascade,
  name text not null,
  job_title text,
  email text,
  phone text,
  whatsapp_phone text,
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger supplier_contacts_set_updated_at
  before update on public.supplier_contacts
  for each row execute function public.set_updated_at();

create index supplier_contacts_supplier_idx
  on public.supplier_contacts (supplier_id, is_active);

-- Seed categories for Master Touch org
insert into public.supplier_categories (organization_id, code, name_ar, name_en)
select
  '11111111-1111-1111-1111-111111111111',
  c.code, c.name_ar, c.name_en
from (values
  ('ELEC', 'كهرباء', 'Electrical'),
  ('SMART', 'أنظمة ذكية', 'Smart Systems'),
  ('HVAC', 'تكييف وتهوية', 'HVAC'),
  ('PLUM', 'سباكة', 'Plumbing'),
  ('FIRE', 'مكافحة حريق', 'Fire Fighting'),
  ('CIVIL', 'مدني', 'Civil'),
  ('FURN', 'أثاث', 'Furniture'),
  ('INT', 'مواد داخلية', 'Interior Materials'),
  ('RENT', 'تأجير معدات', 'Equipment Rental'),
  ('SUB', 'مقاول باطن', 'Subcontractor'),
  ('GEN', 'مورد عام', 'General Supplier')
) as c(code, name_ar, name_en)
on conflict (organization_id, code) do nothing;


-- ===== 032_project_budget.sql =====

-- Master Touch OS — 032
-- Cost categories, project budgets, VAT configuration.

create table public.vat_rate_configs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null default 'standard',
  name_ar text not null,
  name_en text not null,
  rate_percent numeric(6, 3) not null check (rate_percent >= 0 and rate_percent <= 100),
  is_default boolean not null default false,
  effective_from date not null default (timezone('utc', now()))::date,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code),
  check (effective_to is null or effective_to >= effective_from)
);

create table public.cost_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create trigger cost_categories_set_updated_at
  before update on public.cost_categories
  for each row execute function public.set_updated_at();

create type public.budget_status as enum (
  'draft',
  'active',
  'revised',
  'locked',
  'archived'
);

create table public.project_budgets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  currency text not null default 'SAR',
  status public.budget_status not null default 'draft',
  original_budget_amount numeric(18, 2) not null default 0 check (original_budget_amount >= 0),
  approved_variation_amount numeric(18, 2) not null default 0,
  notes text,
  created_by uuid not null references public.profiles (id),
  approved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (project_id)
);

create trigger project_budgets_set_updated_at
  before update on public.project_budgets
  for each row execute function public.set_updated_at();

create table public.project_budget_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  budget_id uuid not null references public.project_budgets (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  cost_category_id uuid references public.cost_categories (id) on delete set null,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  line_no integer not null default 1,
  description text not null,
  quantity numeric(18, 4) not null default 1 check (quantity >= 0),
  unit text,
  unit_cost numeric(18, 4) not null default 0 check (unit_cost >= 0),
  original_amount numeric(18, 2) not null default 0 check (original_amount >= 0),
  approved_variation_amount numeric(18, 2) not null default 0,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (budget_id, line_no)
);

create trigger project_budget_items_set_updated_at
  before update on public.project_budget_items
  for each row execute function public.set_updated_at();

create index project_budget_items_project_idx on public.project_budget_items (project_id);
create index project_budget_items_category_idx on public.project_budget_items (cost_category_id);

-- Derived helpers (views for current budget = original + approved variations)
create or replace view public.project_budget_item_totals as
select
  i.*,
  (i.original_amount + i.approved_variation_amount) as current_budget_amount
from public.project_budget_items i;

create or replace view public.project_budget_totals as
select
  b.id as budget_id,
  b.project_id,
  b.organization_id,
  b.currency,
  b.status,
  b.original_budget_amount,
  b.approved_variation_amount,
  (b.original_budget_amount + b.approved_variation_amount) as current_budget_amount
from public.project_budgets b;

-- Seed cost categories + default VAT (15% placeholder — admin must confirm)
insert into public.cost_categories (organization_id, code, name_ar, name_en)
select
  '11111111-1111-1111-1111-111111111111',
  c.code, c.name_ar, c.name_en
from (values
  ('MAT', 'مواد', 'Materials'),
  ('SUB', 'مقاولو باطن', 'Subcontractors'),
  ('LAB', 'عمالة', 'Labor'),
  ('EQP', 'معدات', 'Equipment'),
  ('TRN', 'نقل', 'Transportation'),
  ('SITE', 'مصاريف موقع', 'Site Expenses'),
  ('ENG', 'هندسة', 'Engineering'),
  ('PRM', 'تصاريح', 'Permits'),
  ('TST', 'اختبارات', 'Testing'),
  ('TMP', 'أعمال مؤقتة', 'Temporary Works'),
  ('MSC', 'متنوعة', 'Miscellaneous')
) as c(code, name_ar, name_en)
on conflict (organization_id, code) do nothing;

insert into public.vat_rate_configs (
  organization_id, code, name_ar, name_en, rate_percent, is_default, is_active
) values (
  '11111111-1111-1111-1111-111111111111',
  'standard',
  'ضريبة القيمة المضافة القياسية',
  'Standard VAT',
  15.000,
  true,
  true
)
on conflict (organization_id, code) do nothing;

comment on table public.vat_rate_configs is
  'Configurable VAT rates. Seeded 15% is a PLACEHOLDER — confirm with admin before production use.';


-- ===== 033_purchase_requests.sql =====

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


-- ===== 034_rfq.sql =====

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


-- ===== 035_quotations.sql =====

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


-- ===== 036_purchase_orders.sql =====

-- Master Touch OS — 036
-- Purchase Orders + items + issued immutability.

create type public.purchase_order_status as enum (
  'draft',
  'pending_approval',
  'approved',
  'issued',
  'partially_delivered',
  'delivered',
  'partially_invoiced',
  'invoiced',
  'closed',
  'cancelled'
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  rfq_id uuid references public.rfqs (id) on delete set null,
  quotation_id uuid references public.supplier_quotations (id) on delete set null,
  po_number text not null,
  currency text not null default 'SAR',
  subtotal numeric(18, 2) not null default 0 check (subtotal >= 0),
  discount numeric(18, 2) not null default 0 check (discount >= 0),
  vat_rate_percent numeric(6, 3) not null default 0 check (vat_rate_percent >= 0),
  vat_amount numeric(18, 2) not null default 0 check (vat_amount >= 0),
  total numeric(18, 2) not null default 0 check (total >= 0),
  payment_terms text,
  delivery_terms text,
  delivery_address text,
  required_delivery_date date,
  issue_date date,
  issued_at timestamptz,
  status public.purchase_order_status not null default 'draft',
  approval_request_id uuid references public.approval_requests (id) on delete set null,
  approved_by uuid references public.profiles (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, po_number)
);

create trigger purchase_orders_set_updated_at
  before update on public.purchase_orders
  for each row execute function public.set_updated_at();

create index purchase_orders_project_idx on public.purchase_orders (project_id, status);
create index purchase_orders_supplier_idx on public.purchase_orders (supplier_id, status);

create table public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders (id) on delete cascade,
  line_no integer not null default 1,
  description text not null,
  quantity numeric(18, 4) not null check (quantity > 0),
  unit text,
  unit_price numeric(18, 4) not null default 0 check (unit_price >= 0),
  vat_amount numeric(18, 2) not null default 0 check (vat_amount >= 0),
  line_total numeric(18, 2) not null default 0 check (line_total >= 0),
  budget_item_id uuid references public.project_budget_items (id) on delete set null,
  purchase_request_item_id uuid references public.purchase_request_items (id) on delete set null,
  quotation_item_id uuid references public.supplier_quotation_items (id) on delete set null,
  related_material_submittal_id uuid references public.material_submittals (id) on delete set null,
  expected_delivery_date date,
  ordered_quantity numeric(18, 4) not null default 0,
  received_quantity numeric(18, 4) not null default 0 check (received_quantity >= 0),
  invoiced_quantity numeric(18, 4) not null default 0 check (invoiced_quantity >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  unique (purchase_order_id, line_no),
  check (received_quantity <= quantity + 0.0001),
  check (invoiced_quantity <= quantity + 0.0001)
);

-- Issued PO header immutability
create or replace function public.protect_issued_purchase_order()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return new;
  end if;
  if old.status = 'issued' or old.issued_at is not null then
    if new.supplier_id is distinct from old.supplier_id
       or new.currency is distinct from old.currency
       or new.subtotal is distinct from old.subtotal
       or new.discount is distinct from old.discount
       or new.vat_amount is distinct from old.vat_amount
       or new.total is distinct from old.total
       or new.payment_terms is distinct from old.payment_terms
       or new.delivery_terms is distinct from old.delivery_terms
       or new.po_number is distinct from old.po_number then
      raise exception 'Issued purchase orders are immutable'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger purchase_orders_protect_issued
  before update on public.purchase_orders
  for each row execute function public.protect_issued_purchase_order();

create or replace function public.protect_issued_purchase_order_items()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_status public.purchase_order_status;
  v_issued timestamptz;
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select status, issued_at into v_status, v_issued
  from public.purchase_orders
  where id = coalesce(new.purchase_order_id, old.purchase_order_id);

  if v_status = 'issued' or v_issued is not null then
    if tg_op in ('INSERT', 'DELETE') then
      raise exception 'Issued purchase order items are immutable'
        using errcode = 'P0001';
    end if;
    if new.description is distinct from old.description
       or new.quantity is distinct from old.quantity
       or new.unit_price is distinct from old.unit_price
       or new.line_total is distinct from old.line_total then
      raise exception 'Issued purchase order items are immutable'
        using errcode = 'P0001';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger purchase_order_items_protect_issued
  before insert or update or delete on public.purchase_order_items
  for each row execute function public.protect_issued_purchase_order_items();


-- ===== 037_goods_receipts.sql =====

-- Master Touch OS — 037
-- Goods / material receipts.

create type public.goods_receipt_status as enum (
  'draft',
  'received',
  'partially_accepted',
  'accepted',
  'rejected',
  'closed'
);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders (id) on delete restrict,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  receipt_number text not null,
  delivery_date date not null default (timezone('utc', now()))::date,
  received_by uuid references public.profiles (id) on delete set null,
  location text,
  delivery_note_number text,
  attachment_document_id uuid references public.documents (id) on delete set null,
  status public.goods_receipt_status not null default 'draft',
  notes text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, receipt_number)
);

create trigger goods_receipts_set_updated_at
  before update on public.goods_receipts
  for each row execute function public.set_updated_at();

create index goods_receipts_po_idx on public.goods_receipts (purchase_order_id, status);
create index goods_receipts_project_idx on public.goods_receipts (project_id, status);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  goods_receipt_id uuid not null references public.goods_receipts (id) on delete cascade,
  purchase_order_item_id uuid not null references public.purchase_order_items (id) on delete restrict,
  received_quantity numeric(18, 4) not null check (received_quantity >= 0),
  accepted_quantity numeric(18, 4) not null default 0 check (accepted_quantity >= 0),
  rejected_quantity numeric(18, 4) not null default 0 check (rejected_quantity >= 0),
  rejection_reason text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  check (accepted_quantity + rejected_quantity <= received_quantity + 0.0001)
);

create index goods_receipt_items_gr_idx on public.goods_receipt_items (goods_receipt_id);
create index goods_receipt_items_po_item_idx on public.goods_receipt_items (purchase_order_item_id);


-- ===== 038_supplier_invoices_payments.sql =====

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


-- ===== 039_project_contracts.sql =====

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


-- ===== 040_client_valuations.sql =====

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


-- ===== 041_variations.sql =====

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


-- ===== 042_phase3_rbac.sql =====

-- Master Touch OS — 042
-- Phase 3 RBAC permissions and role mappings.

insert into public.permissions (key, resource, action, description_ar, description_en) values
  ('supplier.read', 'supplier', 'read', 'عرض الموردين', 'Read suppliers'),
  ('supplier.manage', 'supplier', 'manage', 'إدارة الموردين', 'Manage suppliers'),
  ('procurement.read', 'procurement', 'read', 'عرض المشتريات', 'Read procurement'),
  ('procurement.manage', 'procurement', 'manage', 'إدارة المشتريات', 'Manage procurement'),
  ('purchase_request.create', 'purchase_request', 'create', 'إنشاء طلب شراء', 'Create purchase request'),
  ('purchase_request.read', 'purchase_request', 'read', 'عرض طلبات الشراء', 'Read purchase request'),
  ('purchase_request.approve', 'purchase_request', 'approve', 'اعتماد طلب شراء', 'Approve purchase request'),
  ('rfq.create', 'rfq', 'create', 'إنشاء طلب عرض سعر', 'Create RFQ'),
  ('rfq.read', 'rfq', 'read', 'عرض طلبات عروض الأسعار', 'Read RFQ'),
  ('rfq.issue', 'rfq', 'issue', 'إصدار طلب عرض سعر', 'Issue RFQ'),
  ('rfq.manage', 'rfq', 'manage', 'إدارة طلبات عروض الأسعار', 'Manage RFQ'),
  ('quotation.create', 'quotation', 'create', 'تسجيل عرض سعر', 'Create quotation'),
  ('quotation.read', 'quotation', 'read', 'عرض عروض الأسعار', 'Read quotation'),
  ('quotation.compare', 'quotation', 'compare', 'مقارنة عروض الأسعار', 'Compare quotations'),
  ('quotation.recommend', 'quotation', 'recommend', 'توصية مورد', 'Recommend quotation'),
  ('purchase_order.create', 'purchase_order', 'create', 'إنشاء أمر شراء', 'Create purchase order'),
  ('purchase_order.read', 'purchase_order', 'read', 'عرض أوامر الشراء', 'Read purchase order'),
  ('purchase_order.approve', 'purchase_order', 'approve', 'اعتماد أمر شراء', 'Approve purchase order'),
  ('purchase_order.issue', 'purchase_order', 'issue', 'إصدار أمر شراء', 'Issue purchase order'),
  ('goods_receipt.create', 'goods_receipt', 'create', 'إنشاء استلام مواد', 'Create goods receipt'),
  ('goods_receipt.read', 'goods_receipt', 'read', 'عرض استلام المواد', 'Read goods receipt'),
  ('goods_receipt.manage', 'goods_receipt', 'manage', 'إدارة استلام المواد', 'Manage goods receipt'),
  ('supplier_invoice.create', 'supplier_invoice', 'create', 'تسجيل فاتورة مورد', 'Create supplier invoice'),
  ('supplier_invoice.read', 'supplier_invoice', 'read', 'عرض فواتير الموردين', 'Read supplier invoice'),
  ('supplier_invoice.review', 'supplier_invoice', 'review', 'مراجعة فاتورة مورد', 'Review supplier invoice'),
  ('supplier_invoice.approve', 'supplier_invoice', 'approve', 'اعتماد فاتورة مورد للصرف', 'Approve supplier invoice'),
  ('supplier_payment.read', 'supplier_payment', 'read', 'عرض دفعات الموردين', 'Read supplier payment'),
  ('supplier_payment.record', 'supplier_payment', 'record', 'تسجيل دفعة مورد', 'Record supplier payment'),
  ('supplier_payment.approve', 'supplier_payment', 'approve', 'اعتماد دفعة مورد', 'Approve supplier payment'),
  ('project_budget.read', 'project_budget', 'read', 'عرض ميزانية المشروع', 'Read project budget'),
  ('project_budget.manage', 'project_budget', 'manage', 'إدارة ميزانية المشروع', 'Manage project budget'),
  ('client_valuation.create', 'client_valuation', 'create', 'إنشاء مستخلص', 'Create client valuation'),
  ('client_valuation.read', 'client_valuation', 'read', 'عرض المستخلصات', 'Read client valuation'),
  ('client_valuation.submit', 'client_valuation', 'submit', 'تقديم مستخلص', 'Submit client valuation'),
  ('client_valuation.approve', 'client_valuation', 'approve', 'اعتماد مستخلص', 'Approve client valuation'),
  ('client_invoice.create', 'client_invoice', 'create', 'إنشاء فاتورة عميل', 'Create client invoice'),
  ('client_invoice.read', 'client_invoice', 'read', 'عرض فواتير العملاء', 'Read client invoice'),
  ('client_invoice.issue', 'client_invoice', 'issue', 'إصدار فاتورة عميل', 'Issue client invoice'),
  ('client_payment.read', 'client_payment', 'read', 'عرض مقبوضات العملاء', 'Read client payment'),
  ('client_payment.record', 'client_payment', 'record', 'تسجيل مقبوض عميل', 'Record client payment'),
  ('variation.create', 'variation', 'create', 'إنشاء أمر تغيير', 'Create variation'),
  ('variation.read', 'variation', 'read', 'عرض أوامر التغيير', 'Read variation'),
  ('variation.submit', 'variation', 'submit', 'تقديم أمر تغيير', 'Submit variation'),
  ('variation.approve', 'variation', 'approve', 'اعتماد أمر تغيير', 'Approve variation'),
  ('commercial_reports.read', 'commercial_reports', 'read', 'عرض التقارير التجارية', 'Read commercial reports')
on conflict (key) do nothing;

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'super_admin'
  and (
    p.key like 'supplier.%'
    or p.key like 'procurement.%'
    or p.key like 'purchase_request.%'
    or p.key like 'rfq.%'
    or p.key like 'quotation.%'
    or p.key like 'purchase_order.%'
    or p.key like 'goods_receipt.%'
    or p.key like 'supplier_invoice.%'
    or p.key like 'supplier_payment.%'
    or p.key like 'project_budget.%'
    or p.key like 'client_valuation.%'
    or p.key like 'client_invoice.%'
    or p.key like 'client_payment.%'
    or p.key like 'variation.%'
    or p.key = 'commercial_reports.read'
    or p.key in ('finance.read', 'finance.manage')
  )
on conflict do nothing;

insert into public.role_permissions (role_id, permission_key)
select r.id, x.permission_key
from public.roles r
join (values
  ('general_manager', 'supplier.read'),
  ('general_manager', 'procurement.read'),
  ('general_manager', 'purchase_request.read'),
  ('general_manager', 'purchase_request.approve'),
  ('general_manager', 'rfq.read'),
  ('general_manager', 'quotation.read'),
  ('general_manager', 'purchase_order.read'),
  ('general_manager', 'purchase_order.approve'),
  ('general_manager', 'supplier_invoice.read'),
  ('general_manager', 'supplier_invoice.approve'),
  ('general_manager', 'supplier_payment.read'),
  ('general_manager', 'supplier_payment.approve'),
  ('general_manager', 'project_budget.read'),
  ('general_manager', 'finance.read'),
  ('general_manager', 'finance.manage'),
  ('general_manager', 'client_valuation.read'),
  ('general_manager', 'client_valuation.approve'),
  ('general_manager', 'client_invoice.read'),
  ('general_manager', 'client_payment.read'),
  ('general_manager', 'variation.read'),
  ('general_manager', 'variation.approve'),
  ('general_manager', 'commercial_reports.read'),
  ('operations_manager', 'supplier.read'),
  ('operations_manager', 'procurement.read'),
  ('operations_manager', 'procurement.manage'),
  ('operations_manager', 'purchase_request.read'),
  ('operations_manager', 'purchase_request.approve'),
  ('operations_manager', 'rfq.read'),
  ('operations_manager', 'rfq.manage'),
  ('operations_manager', 'quotation.read'),
  ('operations_manager', 'purchase_order.read'),
  ('operations_manager', 'purchase_order.approve'),
  ('operations_manager', 'goods_receipt.read'),
  ('operations_manager', 'project_budget.read'),
  ('operations_manager', 'finance.read'),
  ('operations_manager', 'variation.read'),
  ('operations_manager', 'commercial_reports.read'),
  ('project_manager', 'supplier.read'),
  ('project_manager', 'procurement.read'),
  ('project_manager', 'purchase_request.create'),
  ('project_manager', 'purchase_request.read'),
  ('project_manager', 'purchase_request.approve'),
  ('project_manager', 'rfq.read'),
  ('project_manager', 'quotation.read'),
  ('project_manager', 'quotation.compare'),
  ('project_manager', 'purchase_order.read'),
  ('project_manager', 'purchase_order.approve'),
  ('project_manager', 'goods_receipt.read'),
  ('project_manager', 'supplier_invoice.read'),
  ('project_manager', 'project_budget.read'),
  ('project_manager', 'client_valuation.create'),
  ('project_manager', 'client_valuation.read'),
  ('project_manager', 'client_valuation.submit'),
  ('project_manager', 'client_invoice.read'),
  ('project_manager', 'variation.create'),
  ('project_manager', 'variation.read'),
  ('project_manager', 'variation.submit'),
  ('project_manager', 'commercial_reports.read'),
  ('project_engineer', 'purchase_request.create'),
  ('project_engineer', 'purchase_request.read'),
  ('project_engineer', 'rfq.read'),
  ('project_engineer', 'goods_receipt.read'),
  ('project_engineer', 'variation.create'),
  ('project_engineer', 'variation.read'),
  ('engineer', 'purchase_request.create'),
  ('engineer', 'purchase_request.read'),
  ('engineer', 'goods_receipt.create'),
  ('engineer', 'goods_receipt.read'),
  ('procurement_manager', 'supplier.read'),
  ('procurement_manager', 'supplier.manage'),
  ('procurement_manager', 'procurement.read'),
  ('procurement_manager', 'procurement.manage'),
  ('procurement_manager', 'purchase_request.read'),
  ('procurement_manager', 'purchase_request.approve'),
  ('procurement_manager', 'rfq.create'),
  ('procurement_manager', 'rfq.read'),
  ('procurement_manager', 'rfq.issue'),
  ('procurement_manager', 'rfq.manage'),
  ('procurement_manager', 'quotation.create'),
  ('procurement_manager', 'quotation.read'),
  ('procurement_manager', 'quotation.compare'),
  ('procurement_manager', 'quotation.recommend'),
  ('procurement_manager', 'purchase_order.create'),
  ('procurement_manager', 'purchase_order.read'),
  ('procurement_manager', 'purchase_order.approve'),
  ('procurement_manager', 'purchase_order.issue'),
  ('procurement_manager', 'goods_receipt.create'),
  ('procurement_manager', 'goods_receipt.read'),
  ('procurement_manager', 'goods_receipt.manage'),
  ('procurement_manager', 'supplier_invoice.read'),
  ('procurement_manager', 'supplier_invoice.review'),
  ('procurement_officer', 'supplier.read'),
  ('procurement_officer', 'procurement.read'),
  ('procurement_officer', 'purchase_request.read'),
  ('procurement_officer', 'rfq.create'),
  ('procurement_officer', 'rfq.read'),
  ('procurement_officer', 'rfq.issue'),
  ('procurement_officer', 'quotation.create'),
  ('procurement_officer', 'quotation.read'),
  ('procurement_officer', 'quotation.compare'),
  ('procurement_officer', 'purchase_order.create'),
  ('procurement_officer', 'purchase_order.read'),
  ('procurement_officer', 'goods_receipt.create'),
  ('procurement_officer', 'goods_receipt.read'),
  ('finance_manager', 'supplier.read'),
  ('finance_manager', 'supplier.manage'),
  ('finance_manager', 'procurement.read'),
  ('finance_manager', 'purchase_order.read'),
  ('finance_manager', 'purchase_order.approve'),
  ('finance_manager', 'supplier_invoice.create'),
  ('finance_manager', 'supplier_invoice.read'),
  ('finance_manager', 'supplier_invoice.review'),
  ('finance_manager', 'supplier_invoice.approve'),
  ('finance_manager', 'supplier_payment.read'),
  ('finance_manager', 'supplier_payment.record'),
  ('finance_manager', 'supplier_payment.approve'),
  ('finance_manager', 'project_budget.read'),
  ('finance_manager', 'project_budget.manage'),
  ('finance_manager', 'finance.read'),
  ('finance_manager', 'finance.manage'),
  ('finance_manager', 'client_valuation.read'),
  ('finance_manager', 'client_invoice.create'),
  ('finance_manager', 'client_invoice.read'),
  ('finance_manager', 'client_invoice.issue'),
  ('finance_manager', 'client_payment.read'),
  ('finance_manager', 'client_payment.record'),
  ('finance_manager', 'variation.read'),
  ('finance_manager', 'variation.approve'),
  ('finance_manager', 'commercial_reports.read'),
  ('finance_officer', 'supplier.read'),
  ('finance_officer', 'supplier_invoice.create'),
  ('finance_officer', 'supplier_invoice.read'),
  ('finance_officer', 'supplier_invoice.review'),
  ('finance_officer', 'supplier_payment.read'),
  ('finance_officer', 'supplier_payment.record'),
  ('finance_officer', 'project_budget.read'),
  ('finance_officer', 'finance.read'),
  ('finance_officer', 'client_invoice.read'),
  ('finance_officer', 'client_payment.read'),
  ('finance_officer', 'client_payment.record'),
  ('finance_officer', 'commercial_reports.read')
) as x(code, permission_key) on x.code = r.code
on conflict do nothing;


-- ===== 043_phase3_rls.sql =====

-- Master Touch OS — 043
-- Phase 3 RLS: project access AND commercial/finance permission.

alter table public.supplier_categories enable row level security;
alter table public.supplier_counters enable row level security;
alter table public.suppliers enable row level security;
alter table public.supplier_contacts enable row level security;
alter table public.vat_rate_configs enable row level security;
alter table public.cost_categories enable row level security;
alter table public.project_budgets enable row level security;
alter table public.project_budget_items enable row level security;
alter table public.commercial_number_counters enable row level security;
alter table public.purchase_requests enable row level security;
alter table public.purchase_request_items enable row level security;
alter table public.rfqs enable row level security;
alter table public.rfq_items enable row level security;
alter table public.rfq_suppliers enable row level security;
alter table public.supplier_quotations enable row level security;
alter table public.supplier_quotation_items enable row level security;
alter table public.quotation_comparisons enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;
alter table public.supplier_invoices enable row level security;
alter table public.supplier_invoice_items enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.project_contracts enable row level security;
alter table public.contract_milestones enable row level security;
alter table public.client_valuations enable row level security;
alter table public.client_invoices enable row level security;
alter table public.client_payments enable row level security;
alter table public.variations enable row level security;
alter table public.approval_threshold_rules enable row level security;

-- Supplier categories / cost categories / VAT: org members with supplier or finance read
drop policy if exists supplier_categories_select on public.supplier_categories;
create policy supplier_categories_select on public.supplier_categories
  for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists supplier_categories_write on public.supplier_categories;
create policy supplier_categories_write on public.supplier_categories
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

drop policy if exists cost_categories_select on public.cost_categories;
create policy cost_categories_select on public.cost_categories
  for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists cost_categories_write on public.cost_categories;
create policy cost_categories_write on public.cost_categories
  for all to authenticated
  using (public.has_permission('project_budget.manage', organization_id)
    or public.has_permission('finance.manage', organization_id))
  with check (public.has_permission('project_budget.manage', organization_id)
    or public.has_permission('finance.manage', organization_id));

drop policy if exists vat_rate_configs_select on public.vat_rate_configs;
create policy vat_rate_configs_select on public.vat_rate_configs
  for select to authenticated
  using (
    public.has_permission('finance.read', organization_id)
    or public.has_permission('procurement.read', organization_id)
  );

drop policy if exists vat_rate_configs_write on public.vat_rate_configs;
create policy vat_rate_configs_write on public.vat_rate_configs
  for all to authenticated
  using (public.has_permission('finance.manage', organization_id))
  with check (public.has_permission('finance.manage', organization_id));

-- Suppliers: non-sensitive columns via table; IBAN restricted by app views/RPC
drop policy if exists suppliers_select on public.suppliers;
create policy suppliers_select on public.suppliers
  for select to authenticated
  using (
    public.is_organization_member(organization_id)
    and public.has_permission('supplier.read', organization_id)
  );

drop policy if exists suppliers_write on public.suppliers;
create policy suppliers_write on public.suppliers
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

drop policy if exists supplier_contacts_select on public.supplier_contacts;
create policy supplier_contacts_select on public.supplier_contacts
  for select to authenticated
  using (
    public.is_organization_member(organization_id)
    and public.has_permission('supplier.read', organization_id)
  );

drop policy if exists supplier_contacts_write on public.supplier_contacts;
create policy supplier_contacts_write on public.supplier_contacts
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

drop policy if exists supplier_counters_all on public.supplier_counters;
create policy supplier_counters_all on public.supplier_counters
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

-- Helper macro pattern for project commercial tables
-- Budgets
drop policy if exists project_budgets_select on public.project_budgets;
create policy project_budgets_select on public.project_budgets
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('project_budget.read', project_id)
  );

drop policy if exists project_budgets_write on public.project_budgets;
create policy project_budgets_write on public.project_budgets
  for all to authenticated
  using (public.has_project_permission('project_budget.manage', project_id))
  with check (public.has_project_permission('project_budget.manage', project_id));

drop policy if exists project_budget_items_select on public.project_budget_items;
create policy project_budget_items_select on public.project_budget_items
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('project_budget.read', project_id)
  );

drop policy if exists project_budget_items_write on public.project_budget_items;
create policy project_budget_items_write on public.project_budget_items
  for all to authenticated
  using (public.has_project_permission('project_budget.manage', project_id))
  with check (public.has_project_permission('project_budget.manage', project_id));

-- Purchase requests
drop policy if exists purchase_requests_select on public.purchase_requests;
create policy purchase_requests_select on public.purchase_requests
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('purchase_request.read', project_id)
  );

drop policy if exists purchase_requests_insert on public.purchase_requests;
create policy purchase_requests_insert on public.purchase_requests
  for insert to authenticated
  with check (public.has_project_permission('purchase_request.create', project_id));

drop policy if exists purchase_requests_update on public.purchase_requests;
create policy purchase_requests_update on public.purchase_requests
  for update to authenticated
  using (
    public.has_project_permission('purchase_request.create', project_id)
    or public.has_project_permission('purchase_request.approve', project_id)
    or public.has_project_permission('procurement.manage', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists purchase_request_items_select on public.purchase_request_items;
create policy purchase_request_items_select on public.purchase_request_items
  for select to authenticated
  using (exists (
    select 1 from public.purchase_requests pr
    where pr.id = purchase_request_id
      and public.can_access_project(pr.project_id)
      and public.has_project_permission('purchase_request.read', pr.project_id)
  ));

drop policy if exists purchase_request_items_write on public.purchase_request_items;
create policy purchase_request_items_write on public.purchase_request_items
  for all to authenticated
  using (exists (
    select 1 from public.purchase_requests pr
    where pr.id = purchase_request_id
      and public.has_project_permission('purchase_request.create', pr.project_id)
  ))
  with check (exists (
    select 1 from public.purchase_requests pr
    where pr.id = purchase_request_id
      and public.has_project_permission('purchase_request.create', pr.project_id)
  ));

-- RFQ
drop policy if exists rfqs_select on public.rfqs;
create policy rfqs_select on public.rfqs
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('rfq.read', project_id));

drop policy if exists rfqs_insert on public.rfqs;
create policy rfqs_insert on public.rfqs
  for insert to authenticated
  with check (public.has_project_permission('rfq.create', project_id));

drop policy if exists rfqs_update on public.rfqs;
create policy rfqs_update on public.rfqs
  for update to authenticated
  using (
    public.has_project_permission('rfq.manage', project_id)
    or public.has_project_permission('rfq.issue', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists rfq_items_all on public.rfq_items;
create policy rfq_items_all on public.rfq_items
  for all to authenticated
  using (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and public.can_access_project(r.project_id)
      and public.has_project_permission('rfq.read', r.project_id)
  ))
  with check (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and public.has_project_permission('rfq.create', r.project_id)
  ));

drop policy if exists rfq_suppliers_all on public.rfq_suppliers;
create policy rfq_suppliers_all on public.rfq_suppliers
  for all to authenticated
  using (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and public.can_access_project(r.project_id)
      and public.has_project_permission('rfq.read', r.project_id)
  ))
  with check (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and (
      public.has_project_permission('rfq.issue', r.project_id)
      or public.has_project_permission('rfq.manage', r.project_id)
    )
  ));

-- Quotations
drop policy if exists supplier_quotations_select on public.supplier_quotations;
create policy supplier_quotations_select on public.supplier_quotations
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('quotation.read', project_id));

drop policy if exists supplier_quotations_write on public.supplier_quotations;
create policy supplier_quotations_write on public.supplier_quotations
  for all to authenticated
  using (
    public.has_project_permission('quotation.create', project_id)
    or public.has_project_permission('quotation.compare', project_id)
  )
  with check (public.has_project_permission('quotation.create', project_id));

drop policy if exists supplier_quotation_items_all on public.supplier_quotation_items;
create policy supplier_quotation_items_all on public.supplier_quotation_items
  for all to authenticated
  using (exists (
    select 1 from public.supplier_quotations q
    where q.id = quotation_id and public.can_access_project(q.project_id)
      and public.has_project_permission('quotation.read', q.project_id)
  ))
  with check (exists (
    select 1 from public.supplier_quotations q
    where q.id = quotation_id and public.has_project_permission('quotation.create', q.project_id)
  ));

drop policy if exists quotation_comparisons_all on public.quotation_comparisons;
create policy quotation_comparisons_all on public.quotation_comparisons
  for all to authenticated
  using (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('quotation.compare', project_id)
      or public.has_project_permission('quotation.recommend', project_id)
      or public.has_project_permission('quotation.read', project_id)
    )
  )
  with check (
    public.has_project_permission('quotation.compare', project_id)
    or public.has_project_permission('quotation.recommend', project_id)
  );

-- Purchase orders
drop policy if exists purchase_orders_select on public.purchase_orders;
create policy purchase_orders_select on public.purchase_orders
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('purchase_order.read', project_id));

drop policy if exists purchase_orders_insert on public.purchase_orders;
create policy purchase_orders_insert on public.purchase_orders
  for insert to authenticated
  with check (public.has_project_permission('purchase_order.create', project_id));

drop policy if exists purchase_orders_update on public.purchase_orders;
create policy purchase_orders_update on public.purchase_orders
  for update to authenticated
  using (
    public.has_project_permission('purchase_order.create', project_id)
    or public.has_project_permission('purchase_order.approve', project_id)
    or public.has_project_permission('purchase_order.issue', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists purchase_order_items_all on public.purchase_order_items;
create policy purchase_order_items_all on public.purchase_order_items
  for all to authenticated
  using (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.can_access_project(po.project_id)
      and public.has_project_permission('purchase_order.read', po.project_id)
  ))
  with check (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.has_project_permission('purchase_order.create', po.project_id)
  ));

-- Goods receipts
drop policy if exists goods_receipts_select on public.goods_receipts;
create policy goods_receipts_select on public.goods_receipts
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('goods_receipt.read', project_id));

drop policy if exists goods_receipts_write on public.goods_receipts;
create policy goods_receipts_write on public.goods_receipts
  for all to authenticated
  using (
    public.has_project_permission('goods_receipt.create', project_id)
    or public.has_project_permission('goods_receipt.manage', project_id)
  )
  with check (
    public.has_project_permission('goods_receipt.create', project_id)
    or public.has_project_permission('goods_receipt.manage', project_id)
  );

drop policy if exists goods_receipt_items_all on public.goods_receipt_items;
create policy goods_receipt_items_all on public.goods_receipt_items
  for all to authenticated
  using (exists (
    select 1 from public.goods_receipts g
    where g.id = goods_receipt_id
      and public.can_access_project(g.project_id)
      and public.has_project_permission('goods_receipt.read', g.project_id)
  ))
  with check (exists (
    select 1 from public.goods_receipts g
    where g.id = goods_receipt_id
      and public.has_project_permission('goods_receipt.create', g.project_id)
  ));

-- Supplier invoices / payments (finance-sensitive)
drop policy if exists supplier_invoices_select on public.supplier_invoices;
create policy supplier_invoices_select on public.supplier_invoices
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('supplier_invoice.read', project_id)
  );

drop policy if exists supplier_invoices_write on public.supplier_invoices;
create policy supplier_invoices_write on public.supplier_invoices
  for all to authenticated
  using (
    public.has_project_permission('supplier_invoice.create', project_id)
    or public.has_project_permission('supplier_invoice.review', project_id)
    or public.has_project_permission('supplier_invoice.approve', project_id)
  )
  with check (
    public.has_project_permission('supplier_invoice.create', project_id)
    or public.has_project_permission('supplier_invoice.review', project_id)
    or public.has_project_permission('supplier_invoice.approve', project_id)
  );

drop policy if exists supplier_invoice_items_all on public.supplier_invoice_items;
create policy supplier_invoice_items_all on public.supplier_invoice_items
  for all to authenticated
  using (exists (
    select 1 from public.supplier_invoices i
    where i.id = supplier_invoice_id
      and public.can_access_project(i.project_id)
      and public.has_project_permission('supplier_invoice.read', i.project_id)
  ))
  with check (exists (
    select 1 from public.supplier_invoices i
    where i.id = supplier_invoice_id
      and public.has_project_permission('supplier_invoice.create', i.project_id)
  ));

drop policy if exists supplier_payments_select on public.supplier_payments;
create policy supplier_payments_select on public.supplier_payments
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('supplier_payment.read', project_id)
  );

drop policy if exists supplier_payments_write on public.supplier_payments;
create policy supplier_payments_write on public.supplier_payments
  for all to authenticated
  using (
    public.has_project_permission('supplier_payment.record', project_id)
    or public.has_project_permission('supplier_payment.approve', project_id)
  )
  with check (public.has_project_permission('supplier_payment.record', project_id));

-- Contracts / valuations / client invoices / payments
drop policy if exists project_contracts_select on public.project_contracts;
create policy project_contracts_select on public.project_contracts
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('finance.read', project_id)
      or public.has_project_permission('client_valuation.read', project_id)
      or public.has_project_permission('commercial_reports.read', project_id)
      or public.has_project_permission('project_budget.read', project_id)
    )
  );

drop policy if exists project_contracts_write on public.project_contracts;
create policy project_contracts_write on public.project_contracts
  for all to authenticated
  using (public.has_project_permission('finance.manage', project_id))
  with check (public.has_project_permission('finance.manage', project_id));

drop policy if exists contract_milestones_all on public.contract_milestones;
create policy contract_milestones_all on public.contract_milestones
  for all to authenticated
  using (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('finance.read', project_id)
      or public.has_project_permission('client_valuation.read', project_id)
    )
  )
  with check (public.has_project_permission('finance.manage', project_id));

drop policy if exists client_valuations_select on public.client_valuations;
create policy client_valuations_select on public.client_valuations
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('client_valuation.read', project_id)
  );

drop policy if exists client_valuations_write on public.client_valuations;
create policy client_valuations_write on public.client_valuations
  for all to authenticated
  using (
    public.has_project_permission('client_valuation.create', project_id)
    or public.has_project_permission('client_valuation.submit', project_id)
    or public.has_project_permission('client_valuation.approve', project_id)
  )
  with check (
    public.has_project_permission('client_valuation.create', project_id)
    or public.has_project_permission('client_valuation.submit', project_id)
  );

drop policy if exists client_invoices_select on public.client_invoices;
create policy client_invoices_select on public.client_invoices
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('client_invoice.read', project_id)
  );

drop policy if exists client_invoices_write on public.client_invoices;
create policy client_invoices_write on public.client_invoices
  for all to authenticated
  using (
    public.has_project_permission('client_invoice.create', project_id)
    or public.has_project_permission('client_invoice.issue', project_id)
  )
  with check (public.has_project_permission('client_invoice.create', project_id));

drop policy if exists client_payments_select on public.client_payments;
create policy client_payments_select on public.client_payments
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('client_payment.read', project_id)
  );

drop policy if exists client_payments_write on public.client_payments;
create policy client_payments_write on public.client_payments
  for all to authenticated
  using (public.has_project_permission('client_payment.record', project_id))
  with check (public.has_project_permission('client_payment.record', project_id));

-- Variations
drop policy if exists variations_select on public.variations;
create policy variations_select on public.variations
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('variation.read', project_id)
  );

drop policy if exists variations_write on public.variations;
create policy variations_write on public.variations
  for all to authenticated
  using (
    public.has_project_permission('variation.create', project_id)
    or public.has_project_permission('variation.submit', project_id)
    or public.has_project_permission('variation.approve', project_id)
  )
  with check (
    public.has_project_permission('variation.create', project_id)
    or public.has_project_permission('variation.submit', project_id)
  );

drop policy if exists approval_threshold_rules_select on public.approval_threshold_rules;
create policy approval_threshold_rules_select on public.approval_threshold_rules
  for select to authenticated
  using (
    public.has_permission('finance.read', organization_id)
    or public.has_permission('procurement.read', organization_id)
    or public.has_permission('settings.manage', organization_id)
  );

drop policy if exists approval_threshold_rules_write on public.approval_threshold_rules;
create policy approval_threshold_rules_write on public.approval_threshold_rules
  for all to authenticated
  using (public.has_permission('settings.manage', organization_id)
    or public.has_permission('finance.manage', organization_id))
  with check (public.has_permission('settings.manage', organization_id)
    or public.has_permission('finance.manage', organization_id));

drop policy if exists commercial_number_counters_all on public.commercial_number_counters;
create policy commercial_number_counters_all on public.commercial_number_counters
  for all to authenticated
  using (public.has_project_permission('procurement.manage', project_id)
    or public.has_project_permission('purchase_request.create', project_id)
    or public.has_project_permission('finance.manage', project_id))
  with check (public.can_access_project(project_id));


-- ===== 044_phase3_rpc.sql =====

-- Master Touch OS — 044
-- Phase 3 RPCs: numbering, supplier create, payments, match, commercial summary/health.

create or replace function public.generate_supplier_code(p_organization_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_value integer;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  insert into public.supplier_counters (organization_id, next_value)
  values (p_organization_id, 1)
  on conflict (organization_id) do update
    set next_value = public.supplier_counters.next_value + 1
  returning next_value into v_value;

  return 'SUP-' || lpad(v_value::text, 4, '0');
end;
$$;

grant execute on function public.generate_supplier_code(uuid) to authenticated;

create or replace function public.generate_commercial_number(
  p_organization_id uuid,
  p_project_id uuid,
  p_doc_type text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_code text;
  v_value integer;
  v_abbr text;
begin
  if not public.can_access_project(p_project_id) then
    raise exception 'FORBIDDEN';
  end if;

  select project_code into v_project_code
  from public.projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_code is null then
    raise exception 'NOT_FOUND';
  end if;

  v_abbr := upper(p_doc_type);

  insert into public.commercial_number_counters (
    organization_id, project_id, doc_type, next_value
  ) values (
    p_organization_id, p_project_id, v_abbr, 1
  )
  on conflict (organization_id, project_id, doc_type) do update
    set next_value = public.commercial_number_counters.next_value + 1
  returning next_value into v_value;

  return format('MT-%s-%s-%s', v_project_code, v_abbr, lpad(v_value::text, 4, '0'));
end;
$$;

grant execute on function public.generate_commercial_number(uuid, uuid, text) to authenticated;

-- Supplier bank details: privileged read only
create or replace function public.get_supplier_banking(p_supplier_id uuid)
returns table (bank_name text, iban text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from public.suppliers where id = p_supplier_id;
  if v_org is null then
    raise exception 'NOT_FOUND';
  end if;
  if not (
    public.has_permission('supplier.manage', v_org)
    or public.has_permission('finance.manage', v_org)
    or public.has_permission('finance.read', v_org)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  return query
  select s.bank_name, s.iban
  from public.suppliers s
  where s.id = p_supplier_id;
end;
$$;

grant execute on function public.get_supplier_banking(uuid) to authenticated;

-- Record supplier payment with overpayment guard
create or replace function public.record_supplier_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_reference text,
  p_payment_method public.payment_method default 'bank_transfer',
  p_bank_reference text default null,
  p_notes text default null
)
returns public.supplier_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.supplier_invoices;
  v_paid numeric(18, 2);
  v_pay public.supplier_payments;
begin
  select * into v_inv from public.supplier_invoices where id = p_invoice_id for update;
  if v_inv.id is null then raise exception 'NOT_FOUND'; end if;

  if not public.has_project_permission('supplier_payment.record', v_inv.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'VALIDATION';
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.supplier_payments
  where supplier_invoice_id = v_inv.id;

  if v_paid + p_amount > v_inv.total + 0.001 then
    raise exception 'VALIDATION: payment exceeds invoice total'
      using errcode = 'P0001';
  end if;

  insert into public.supplier_payments (
    organization_id, project_id, supplier_id, supplier_invoice_id,
    payment_reference, amount, payment_date, payment_method,
    bank_reference, notes, recorded_by
  ) values (
    v_inv.organization_id, v_inv.project_id, v_inv.supplier_id, v_inv.id,
    p_payment_reference, p_amount, p_payment_date, p_payment_method,
    p_bank_reference, p_notes, auth.uid()
  ) returning * into v_pay;

  v_paid := v_paid + p_amount;
  update public.supplier_invoices
  set status = case
        when v_paid >= v_inv.total then 'paid'::public.supplier_invoice_status
        else 'partially_paid'::public.supplier_invoice_status
      end
  where id = v_inv.id;

  perform public.log_audit(
    v_inv.organization_id, 'supplier_payment.recorded', 'supplier_payment', v_pay.id,
    null, to_jsonb(v_pay)
  );
  perform public.emit_domain_event(
    v_inv.organization_id, 'supplier_payment.recorded', 'supplier_payment', v_pay.id,
    jsonb_build_object('amount', p_amount, 'invoice_id', v_inv.id)
  );

  return v_pay;
end;
$$;

grant execute on function public.record_supplier_payment(uuid, numeric, date, text, public.payment_method, text, text) to authenticated;

-- Three-way match flags for supplier invoice
create or replace function public.evaluate_supplier_invoice_match(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.supplier_invoices;
  v_po_total numeric(18, 2);
  v_received numeric(18, 4);
  v_ordered numeric(18, 4);
  v_flags jsonb := '[]'::jsonb;
begin
  select * into v_inv from public.supplier_invoices where id = p_invoice_id;
  if v_inv.id is null then raise exception 'NOT_FOUND'; end if;

  if v_inv.purchase_order_id is not null then
    select total into v_po_total from public.purchase_orders where id = v_inv.purchase_order_id;
    if v_inv.total > coalesce(v_po_total, 0) + 0.01 then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'invoice_gt_po', 'severity', 'high'));
    end if;

    select coalesce(sum(quantity), 0), coalesce(sum(received_quantity), 0)
      into v_ordered, v_received
    from public.purchase_order_items
    where purchase_order_id = v_inv.purchase_order_id;

    if v_inv.total > 0 and v_received < v_ordered and v_received = 0 then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'invoice_without_receipt', 'severity', 'medium'));
    end if;
  else
    v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'missing_po', 'severity', 'medium'));
  end if;

  update public.supplier_invoices
  set match_flags = v_flags,
      status = case
        when jsonb_array_length(v_flags) > 0 then 'discrepancy'::public.supplier_invoice_status
        when status = 'received' then 'matched'::public.supplier_invoice_status
        else status
      end
  where id = p_invoice_id;

  if jsonb_array_length(v_flags) > 0 then
    perform public.emit_domain_event(
      v_inv.organization_id, 'supplier_invoice.discrepancy', 'supplier_invoice', p_invoice_id,
      jsonb_build_object('flags', v_flags)
    );
  end if;

  return v_flags;
end;
$$;

grant execute on function public.evaluate_supplier_invoice_match(uuid) to authenticated;

-- Issue PO
create or replace function public.issue_purchase_order(p_po_id uuid)
returns public.purchase_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po public.purchase_orders;
  v_count integer;
begin
  select * into v_po from public.purchase_orders where id = p_po_id for update;
  if v_po.id is null then raise exception 'NOT_FOUND'; end if;
  if v_po.status not in ('approved', 'draft') then raise exception 'CONFLICT'; end if;
  if not public.has_project_permission('purchase_order.issue', v_po.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  select count(*) into v_count from public.purchase_order_items where purchase_order_id = v_po.id;
  if v_count = 0 then raise exception 'VALIDATION'; end if;

  update public.purchase_order_items
  set ordered_quantity = quantity
  where purchase_order_id = v_po.id;

  update public.purchase_orders
  set status = 'issued',
      issue_date = (timezone('utc', now()))::date,
      issued_at = timezone('utc', now())
  where id = v_po.id
  returning * into v_po;

  perform public.log_audit(
    v_po.organization_id, 'purchase_order.issued', 'purchase_order', v_po.id, null, to_jsonb(v_po)
  );
  perform public.emit_domain_event(
    v_po.organization_id, 'purchase_order.issued', 'purchase_order', v_po.id,
    jsonb_build_object('po_number', v_po.po_number, 'total', v_po.total)
  );

  return v_po;
end;
$$;

grant execute on function public.issue_purchase_order(uuid) to authenticated;

-- Apply goods receipt quantities to PO lines (over-receipt blocked)
create or replace function public.post_goods_receipt(p_receipt_id uuid)
returns public.goods_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gr public.goods_receipts;
  r record;
  v_new_received numeric(18, 4);
begin
  select * into v_gr from public.goods_receipts where id = p_receipt_id for update;
  if v_gr.id is null then raise exception 'NOT_FOUND'; end if;
  if not public.has_project_permission('goods_receipt.manage', v_gr.project_id)
     and not public.has_project_permission('goods_receipt.create', v_gr.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  for r in
    select * from public.goods_receipt_items where goods_receipt_id = p_receipt_id
  loop
    select received_quantity + r.accepted_quantity into v_new_received
    from public.purchase_order_items
    where id = r.purchase_order_item_id
    for update;

    if v_new_received > (
      select quantity from public.purchase_order_items where id = r.purchase_order_item_id
    ) + 0.0001 then
      raise exception 'VALIDATION: received quantity exceeds ordered'
        using errcode = 'P0001';
    end if;

    update public.purchase_order_items
    set received_quantity = received_quantity + r.accepted_quantity
    where id = r.purchase_order_item_id;
  end loop;

  update public.goods_receipts
  set status = 'accepted'
  where id = p_receipt_id
  returning * into v_gr;

  -- Update PO delivery status
  update public.purchase_orders po
  set status = case
    when exists (
      select 1 from public.purchase_order_items i
      where i.purchase_order_id = po.id and i.received_quantity < i.quantity
    ) then 'partially_delivered'::public.purchase_order_status
    else 'delivered'::public.purchase_order_status
  end
  where po.id = v_gr.purchase_order_id
    and po.status in ('issued', 'partially_delivered');

  perform public.emit_domain_event(
    v_gr.organization_id, 'goods_receipt.received', 'goods_receipt', v_gr.id,
    jsonb_build_object('receipt_number', v_gr.receipt_number)
  );

  return v_gr;
end;
$$;

grant execute on function public.post_goods_receipt(uuid) to authenticated;

-- Approve variation: preserve original contract; accumulate approved VO amount into budget notes via event
create or replace function public.approve_variation(
  p_variation_id uuid,
  p_approved_amount numeric
)
returns public.variations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vo public.variations;
begin
  select * into v_vo from public.variations where id = p_variation_id for update;
  if v_vo.id is null then raise exception 'NOT_FOUND'; end if;
  if not public.has_project_permission('variation.approve', v_vo.project_id) then
    raise exception 'FORBIDDEN';
  end if;
  if p_approved_amount is null then raise exception 'VALIDATION'; end if;

  update public.variations
  set status = 'approved',
      approved_amount = p_approved_amount,
      approval_date = (timezone('utc', now()))::date
  where id = p_variation_id
  returning * into v_vo;

  -- Bump project budget approved variation total if budget exists
  update public.project_budgets
  set approved_variation_amount = approved_variation_amount + p_approved_amount,
      status = 'revised'
  where project_id = v_vo.project_id;

  perform public.log_audit(
    v_vo.organization_id, 'variation.approved', 'variation', v_vo.id, null, to_jsonb(v_vo)
  );
  perform public.emit_domain_event(
    v_vo.organization_id, 'variation.approved', 'variation', v_vo.id,
    jsonb_build_object('approved_amount', p_approved_amount, 'vo_number', v_vo.vo_number)
  );

  return v_vo;
end;
$$;

grant execute on function public.approve_variation(uuid, numeric) to authenticated;

-- Project commercial summary (derived)
create or replace function public.compute_project_commercial_summary(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_original_contract numeric(18, 2) := 0;
  v_approved_vo numeric(18, 2) := 0;
  v_original_budget numeric(18, 2) := 0;
  v_budget_vo numeric(18, 2) := 0;
  v_committed numeric(18, 2) := 0;
  v_ap numeric(18, 2) := 0;
  v_ar numeric(18, 2) := 0;
  v_invoiced_rev numeric(18, 2) := 0;
  v_collected numeric(18, 2) := 0;
  v_revised_contract numeric(18, 2);
  v_revised_budget numeric(18, 2);
  v_margin numeric(18, 2);
begin
  select organization_id into v_org from public.projects where id = p_project_id;
  if v_org is null then raise exception 'NOT_FOUND'; end if;

  if not public.can_access_project(p_project_id) then
    raise exception 'FORBIDDEN';
  end if;
  if not (
    public.has_project_permission('finance.read', p_project_id)
    or public.has_project_permission('commercial_reports.read', p_project_id)
    or public.has_project_permission('project_budget.read', p_project_id)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  select coalesce(sum(contract_value), 0) into v_original_contract
  from public.project_contracts
  where project_id = p_project_id and status in ('active', 'completed', 'draft');

  select coalesce(sum(coalesce(approved_amount, 0)), 0) into v_approved_vo
  from public.variations
  where project_id = p_project_id and status in ('approved', 'partially_approved');

  select coalesce(original_budget_amount, 0), coalesce(approved_variation_amount, 0)
    into v_original_budget, v_budget_vo
  from public.project_budgets
  where project_id = p_project_id;

  select coalesce(sum(total), 0) into v_committed
  from public.purchase_orders
  where project_id = p_project_id
    and status in ('approved', 'issued', 'partially_delivered', 'delivered', 'partially_invoiced', 'invoiced', 'closed');

  select coalesce(sum(si.total), 0) - coalesce((
    select sum(sp.amount) from public.supplier_payments sp where sp.project_id = p_project_id
  ), 0)
  into v_ap
  from public.supplier_invoices si
  where si.project_id = p_project_id
    and si.status not in ('cancelled', 'rejected');

  select coalesce(sum(total), 0) into v_invoiced_rev
  from public.client_invoices
  where project_id = p_project_id and status in ('issued', 'partially_paid', 'paid', 'overdue');

  select coalesce(sum(amount), 0) into v_collected
  from public.client_payments
  where project_id = p_project_id;

  v_ar := v_invoiced_rev - v_collected;
  v_revised_contract := v_original_contract + v_approved_vo;
  v_revised_budget := v_original_budget + v_budget_vo;
  v_margin := v_revised_contract - greatest(v_committed, v_revised_budget * 0); -- forecast uses committed as proxy

  return jsonb_build_object(
    'original_contract_value', v_original_contract,
    'approved_variations', v_approved_vo,
    'revised_contract_value', v_revised_contract,
    'original_budget', v_original_budget,
    'revised_budget', v_revised_budget,
    'committed_cost', v_committed,
    'accounts_payable', v_ap,
    'invoiced_revenue', v_invoiced_rev,
    'collected_revenue', v_collected,
    'accounts_receivable', v_ar,
    'gross_margin_estimate', v_revised_contract - v_committed
  );
end;
$$;

grant execute on function public.compute_project_commercial_summary(uuid) to authenticated;

create or replace function public.compute_project_commercial_health(p_project_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_summary jsonb;
  v_committed numeric;
  v_revised_budget numeric;
  v_margin numeric;
  v_overdue_ap integer;
  v_overdue_ar integer;
  v_unapproved_vo integer;
begin
  if not public.can_access_project(p_project_id) then
    raise exception 'FORBIDDEN';
  end if;

  v_summary := public.compute_project_commercial_summary(p_project_id);
  v_committed := (v_summary ->> 'committed_cost')::numeric;
  v_revised_budget := (v_summary ->> 'revised_budget')::numeric;
  v_margin := (v_summary ->> 'gross_margin_estimate')::numeric;

  select count(*) into v_overdue_ap
  from public.supplier_invoices
  where project_id = p_project_id
    and due_date < (timezone('utc', now()))::date
    and status in ('received', 'under_review', 'matched', 'discrepancy', 'approved_for_payment', 'partially_paid');

  select count(*) into v_overdue_ar
  from public.client_invoices
  where project_id = p_project_id
    and due_date < (timezone('utc', now()))::date
    and status in ('issued', 'partially_paid', 'overdue');

  select count(*) into v_unapproved_vo
  from public.variations
  where project_id = p_project_id
    and status in ('submitted', 'negotiation', 'under_review')
    and submitted_date is not null
    and submitted_date < (timezone('utc', now()))::date - 14;

  -- RED rules
  if v_revised_budget > 0 and v_committed > v_revised_budget then
    return 'red';
  end if;
  if v_margin < 0 then
    return 'red';
  end if;
  if v_overdue_ar >= 3 or v_overdue_ap >= 5 then
    return 'red';
  end if;

  -- AMBER
  if v_revised_budget > 0 and v_committed > v_revised_budget * 0.9 then
    return 'amber';
  end if;
  if v_overdue_ap > 0 or v_overdue_ar > 0 or v_unapproved_vo > 0 then
    return 'amber';
  end if;

  return 'green';
end;
$$;

grant execute on function public.compute_project_commercial_health(uuid) to authenticated;

comment on function public.compute_project_commercial_health(uuid) is
  'Deterministic commercial health: RED if committed>budget or negative margin or severe overdue AR/AP; AMBER if near budget / overdue / VO pending >14d; else GREEN.';


-- ===== 045_phase3_indexes_cashflow.sql =====

-- Master Touch OS — 045
-- Phase 3 indexes + search trigrams + cashflow helper view.

create extension if not exists pg_trgm;

create index if not exists suppliers_code_trgm_idx
  on public.suppliers using gin (supplier_code gin_trgm_ops);
create index if not exists suppliers_legal_trgm_idx
  on public.suppliers using gin (legal_name gin_trgm_ops);

create index if not exists purchase_requests_number_trgm_idx
  on public.purchase_requests using gin (pr_number gin_trgm_ops);
create index if not exists rfqs_number_trgm_idx
  on public.rfqs using gin (rfq_number gin_trgm_ops);
create index if not exists purchase_orders_number_trgm_idx
  on public.purchase_orders using gin (po_number gin_trgm_ops);
create index if not exists supplier_invoices_number_trgm_idx
  on public.supplier_invoices using gin (invoice_number gin_trgm_ops);
create index if not exists client_invoices_number_trgm_idx
  on public.client_invoices using gin (invoice_number gin_trgm_ops);
create index if not exists client_valuations_number_trgm_idx
  on public.client_valuations using gin (valuation_number gin_trgm_ops);
create index if not exists variations_number_trgm_idx
  on public.variations using gin (vo_number gin_trgm_ops);

-- Simple cash-flow period foundation (expected inflows/outflows by due date)
create or replace view public.project_cashflow_items as
select
  si.organization_id,
  si.project_id,
  'outflow'::text as direction,
  'supplier_invoice'::text as source_type,
  si.id as source_id,
  si.due_date as period_date,
  (si.total - coalesce((
    select sum(sp.amount) from public.supplier_payments sp where sp.supplier_invoice_id = si.id
  ), 0)) as amount,
  si.currency
from public.supplier_invoices si
where si.status not in ('paid', 'cancelled', 'rejected')
  and si.due_date is not null

union all

select
  ci.organization_id,
  ci.project_id,
  'inflow'::text,
  'client_invoice'::text,
  ci.id,
  ci.due_date,
  (ci.total - coalesce((
    select sum(cp.amount) from public.client_payments cp where cp.client_invoice_id = ci.id
  ), 0)),
  ci.currency
from public.client_invoices ci
where ci.status in ('issued', 'partially_paid', 'overdue')
  and ci.due_date is not null;

comment on view public.project_cashflow_items is
  'Foundation cash-flow lines from open supplier AP and client AR due dates. Not corporate treasury.';

