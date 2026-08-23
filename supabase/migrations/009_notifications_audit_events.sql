-- Master Touch OS — 009
-- Notifications, immutable audit trail, and domain event store.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  recipient_profile_id uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  title text not null,
  message text not null,
  entity_type text,
  entity_id uuid,
  priority public.notification_priority not null default 'normal',
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index notifications_recipient_idx
  on public.notifications (recipient_profile_id, created_at desc);
create index notifications_unread_idx
  on public.notifications (recipient_profile_id)
  where read_at is null;

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications (id) on delete cascade,
  channel text not null check (channel in ('in_app', 'email', 'whatsapp', 'push')),
  status text not null default 'pending',
  attempted_at timestamptz,
  error text,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid not null,
  previous_values jsonb,
  new_values jsonb,
  ip_address text,
  user_agent text,
  correlation_id text,
  created_at timestamptz not null default timezone('utc', now())
);

create index audit_logs_org_idx on public.audit_logs (organization_id, created_at desc);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);
create index audit_logs_actor_idx on public.audit_logs (actor_id, created_at desc);

create table public.domain_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  event_type text not null,
  entity_type text not null,
  entity_id uuid not null,
  actor_id uuid references public.profiles (id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  correlation_id text,
  processed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index domain_events_type_idx on public.domain_events (event_type, created_at desc);
create index domain_events_unprocessed_idx
  on public.domain_events (created_at)
  where processed_at is null;
