-- Master Touch OS — 002
-- Multi-tenant organization model.

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  name_en text not null,
  legal_name text,
  commercial_registration text,
  vat_number text,
  logo_path text,
  country text not null default 'SA',
  timezone text not null default 'Asia/Riyadh',
  default_currency text not null default 'SAR',
  status public.organization_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function public.set_updated_at();

create index organizations_status_idx on public.organizations (status);
