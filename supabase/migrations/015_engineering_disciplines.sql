-- Master Touch OS — 015
-- Engineering disciplines and project discipline activation.

create table public.engineering_disciplines (
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

create trigger engineering_disciplines_set_updated_at
  before update on public.engineering_disciplines
  for each row execute function public.set_updated_at();

create index engineering_disciplines_org_idx
  on public.engineering_disciplines (organization_id, is_active);

create table public.project_disciplines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  discipline_id uuid not null references public.engineering_disciplines (id) on delete restrict,
  is_active boolean not null default true,
  activated_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  unique (project_id, discipline_id)
);

create index project_disciplines_project_idx
  on public.project_disciplines (project_id, is_active);

-- Seed Master Touch organization disciplines
insert into public.engineering_disciplines (organization_id, code, name_ar, name_en, description)
select
  '11111111-1111-1111-1111-111111111111',
  d.code,
  d.name_ar,
  d.name_en,
  d.description
from (values
  ('ARCH', 'العمارة / التصميم الداخلي', 'Architecture / Interior', 'Architecture and interior design'),
  ('ELEC', 'الكهرباء', 'Electrical', 'Electrical systems'),
  ('SMART', 'الأنظمة الذكية', 'Smart Systems', 'Smart and low-voltage systems'),
  ('PLUM', 'السباكة', 'Plumbing', 'Plumbing and drainage'),
  ('HVAC', 'التكييف والتهوية', 'HVAC', 'Heating, ventilation and air conditioning'),
  ('MECH', 'الميكانيكا', 'Mechanical', 'Mechanical systems'),
  ('FIRE', 'مكافحة الحريق', 'Fire Fighting', 'Fire protection systems'),
  ('CIVIL', 'المدني', 'Civil', 'Civil works'),
  ('STRUCT', 'الإنشائي', 'Structural', 'Structural engineering'),
  ('GENERAL', 'عام', 'General', 'General / multi-discipline')
) as d(code, name_ar, name_en, description)
on conflict (organization_id, code) do nothing;
