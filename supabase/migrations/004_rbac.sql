-- Master Touch OS — 004
-- Role-based access control.

create table public.permissions (
  key text primary key,
  resource text not null,
  action text not null,
  description_ar text not null,
  description_en text not null
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  is_system boolean not null default false,
  is_external boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create unique index roles_system_code_uidx
  on public.roles (code)
  where organization_id is null;

create trigger roles_set_updated_at
  before update on public.roles
  for each row execute function public.set_updated_at();

create table public.role_permissions (
  role_id uuid not null references public.roles (id) on delete cascade,
  permission_key text not null references public.permissions (key) on delete cascade,
  primary key (role_id, permission_key)
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  role_id uuid not null references public.roles (id) on delete cascade,
  scope_type public.role_scope_type not null default 'organization',
  scope_id uuid,
  granted_by uuid references public.profiles (id) on delete set null,
  granted_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, profile_id, role_id, scope_type, scope_id)
);

create index user_roles_profile_idx on public.user_roles (profile_id, organization_id);
create index user_roles_scope_idx on public.user_roles (scope_type, scope_id);
