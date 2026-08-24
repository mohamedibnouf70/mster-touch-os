-- Master Touch OS — 024
-- Project contacts and formal transmittals.

create type public.project_contact_type as enum (
  'client',
  'consultant',
  'supplier',
  'subcontractor',
  'other'
);

create table public.project_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  company_name text not null,
  contact_name text not null,
  role_title text,
  email text,
  phone text,
  whatsapp_phone text,
  contact_type public.project_contact_type not null default 'other',
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger project_contacts_set_updated_at
  before update on public.project_contacts
  for each row execute function public.set_updated_at();

create index project_contacts_project_idx on public.project_contacts (project_id, contact_type, is_active);

create type public.transmittal_direction as enum ('outgoing', 'incoming');

create type public.transmittal_status as enum (
  'draft',
  'issued',
  'acknowledged',
  'closed',
  'cancelled'
);

create type public.transmittal_purpose as enum (
  'for_approval',
  'for_review',
  'for_information',
  'for_construction',
  'for_record'
);

create table public.transmittals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  transmittal_number text not null,
  direction public.transmittal_direction not null default 'outgoing',
  recipient text not null,
  subject text not null,
  description text,
  issued_by uuid references public.profiles (id) on delete set null,
  issued_date date,
  issued_at timestamptz,
  response_required boolean not null default false,
  response_due date,
  status public.transmittal_status not null default 'draft',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, transmittal_number)
);

create trigger transmittals_set_updated_at
  before update on public.transmittals
  for each row execute function public.set_updated_at();

create index transmittals_project_idx on public.transmittals (project_id, status);

create table public.transmittal_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  transmittal_id uuid not null references public.transmittals (id) on delete cascade,
  document_id uuid not null references public.documents (id) on delete restrict,
  document_version_id uuid not null references public.document_versions (id) on delete restrict,
  purpose public.transmittal_purpose not null default 'for_review',
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (transmittal_id, document_version_id)
);

create index transmittal_items_transmittal_idx on public.transmittal_items (transmittal_id);

-- Issued transmittals and their items are immutable
create or replace function public.protect_issued_transmittal()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'transmittals' then
    if old.status = 'issued' and old.issued_at is not null then
      if new.recipient is distinct from old.recipient
         or new.subject is distinct from old.subject
         or new.description is distinct from old.description
         or new.issued_date is distinct from old.issued_date then
        raise exception 'CONFLICT';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger transmittals_protect_issued
  before update on public.transmittals
  for each row execute function public.protect_issued_transmittal();

create or replace function public.protect_issued_transmittal_items()
returns trigger
language plpgsql
as $$
declare
  v_status public.transmittal_status;
begin
  select status into v_status from public.transmittals where id = coalesce(new.transmittal_id, old.transmittal_id);
  if v_status = 'issued' then
    raise exception 'CONFLICT';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger transmittal_items_protect_issued
  before insert or update or delete on public.transmittal_items
  for each row execute function public.protect_issued_transmittal_items();
