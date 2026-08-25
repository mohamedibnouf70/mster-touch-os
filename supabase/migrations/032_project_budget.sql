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
