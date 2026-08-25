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
