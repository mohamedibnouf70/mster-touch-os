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
