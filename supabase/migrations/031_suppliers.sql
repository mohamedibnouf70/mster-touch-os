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
