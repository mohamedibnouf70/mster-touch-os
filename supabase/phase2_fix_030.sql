-- Master Touch OS — 030
-- Phase 2 live security fixes:
-- 1) Project-scoped access: org-scoped project.read must NOT grant every project
-- 2) Issued transmittal / item immutability enforced by trigger (not silent RLS)

-- =============================================================================
-- A. can_access_project
-- =============================================================================
-- ROOT CAUSE (Phase 1 has_permission + Phase 2 026):
--   has_permission() returns true for ANY requested scope when the user_role
--   has scope_type = 'organization' (org grant is treated as a wildcard).
--   Migration 026 removed the explicit organization-scope project.read call but
--   kept:
--     has_permission('project.read', org, 'project', project_id)
--   which still matched engineers with org-scoped Engineer + project.read.
--
-- AUTHORITATIVE RULE:
--   Org-wide project visibility requires project.read_all (or platform admin).
--   project.read alone requires explicit project membership, PM assignment,
--   or a user_roles row with scope_type = 'project' and scope_id = that project.
-- =============================================================================

create or replace function public.can_access_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.projects pr
    where pr.id = p_project_id
      and (
        public.is_platform_admin()
        or (
          public.is_organization_member(pr.organization_id)
          and (
            -- Organization-wide privileged visibility (GM / Ops / DC / Quality / etc.)
            public.has_permission(
              'project.read_all',
              pr.organization_id,
              'organization',
              null
            )
            -- Explicit project-scoped role grant (exact scope — not org wildcard)
            or exists (
              select 1
              from public.user_roles ur
              join public.roles r on r.id = ur.role_id
              join public.role_permissions rp on rp.role_id = r.id
              join public.profiles p on p.id = ur.profile_id
              join public.organization_members m
                on m.profile_id = ur.profile_id
               and m.organization_id = ur.organization_id
              where ur.profile_id = auth.uid()
                and ur.organization_id = pr.organization_id
                and ur.scope_type = 'project'
                and ur.scope_id = pr.id
                and rp.permission_key = 'project.read'
                and r.is_external = false
                and p.is_active = true
                and m.status = 'active'
            )
            -- Assigned project manager
            or pr.project_manager_id = auth.uid()
            -- Active project membership
            or exists (
              select 1
              from public.project_members pm
              where pm.project_id = pr.id
                and pm.profile_id = auth.uid()
                and pm.is_active = true
            )
          )
        )
      )
  );
$$;

grant execute on function public.can_access_project(uuid) to authenticated;

-- Keep has_project_permission: module permission + corrected can_access_project.
-- Org-scoped module permissions (rfi.read, etc.) remain valid once project access
-- is established via membership / PM / read_all / project-scoped grant.
create or replace function public.has_project_permission(
  p_permission_key text,
  p_project_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.projects pr
    where pr.id = p_project_id
      and (
        public.is_platform_admin()
        or (
          public.can_access_project(p_project_id)
          and (
            public.has_permission(p_permission_key, pr.organization_id, 'organization', null)
            or public.has_permission(p_permission_key, pr.organization_id, 'project', pr.id)
          )
        )
      )
  );
$$;

grant execute on function public.has_project_permission(text, uuid) to authenticated;

-- Ensure projects SELECT uses the corrected helper (single authoritative policy).
-- Old Phase 1 policy already used can_access_project(id); replacing is defensive.
drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects
  for select to authenticated
  using (public.can_access_project(id));

-- =============================================================================
-- B. Issued transmittal immutability
-- =============================================================================
-- ROOT CAUSE:
--   RLS policy required status = 'draft' for ALL writes. For issued items,
--   UPDATE/DELETE USING failed → 0 rows affected, PostgREST returned success
--   with no error, and the BEFORE trigger never fired.
--
-- FIX:
--   INSERT remains draft-only (WITH CHECK raises on violation).
--   UPDATE/DELETE are allowed through RLS for authorized users so the trigger
--   can RAISE when the parent is issued.
-- =============================================================================

create or replace function public.protect_issued_transmittal()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- Service role bypasses for fixture/ops cleanup only (never exposed to browser).
  -- Authenticated application JWTs cannot mutate issued payloads.
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return new;
  end if;

  if old.status = 'issued' then
    if new.status is distinct from old.status
       or new.recipient is distinct from old.recipient
       or new.subject is distinct from old.subject
       or new.description is distinct from old.description
       or new.direction is distinct from old.direction
       or new.transmittal_number is distinct from old.transmittal_number
       or new.issued_date is distinct from old.issued_date
       or new.issued_at is distinct from old.issued_at
       or new.issued_by is distinct from old.issued_by
       or new.project_id is distinct from old.project_id
       or new.organization_id is distinct from old.organization_id
       or new.response_required is distinct from old.response_required
       or new.response_due is distinct from old.response_due then
      raise exception 'Issued transmittals are immutable'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists transmittals_protect_issued on public.transmittals;
create trigger transmittals_protect_issued
  before update on public.transmittals
  for each row execute function public.protect_issued_transmittal();

create or replace function public.protect_issued_transmittal_items()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_status public.transmittal_status;
  v_id uuid;
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  v_id := coalesce(new.transmittal_id, old.transmittal_id);

  select status into v_status
  from public.transmittals
  where id = v_id;

  if v_status = 'issued' then
    raise exception 'Issued transmittal items are immutable'
      using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists transmittal_items_protect_issued on public.transmittal_items;
create trigger transmittal_items_protect_issued
  before insert or update or delete on public.transmittal_items
  for each row execute function public.protect_issued_transmittal_items();

-- Split write policies so UPDATE/DELETE reach the trigger on issued rows.
drop policy if exists transmittal_items_write on public.transmittal_items;
drop policy if exists transmittal_items_insert on public.transmittal_items;
drop policy if exists transmittal_items_update on public.transmittal_items;
drop policy if exists transmittal_items_delete on public.transmittal_items;

-- INSERT: only while draft (WITH CHECK violation → error)
create policy transmittal_items_insert on public.transmittal_items
  for insert to authenticated
  with check (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and t.status = 'draft'
      and public.has_project_permission('transmittal.create', t.project_id)
  ));

-- UPDATE: authorized users; trigger rejects when issued
create policy transmittal_items_update on public.transmittal_items
  for update to authenticated
  using (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and public.has_project_permission('transmittal.create', t.project_id)
  ))
  with check (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and public.has_project_permission('transmittal.create', t.project_id)
  ));

-- DELETE: authorized users; trigger rejects when issued
create policy transmittal_items_delete on public.transmittal_items
  for delete to authenticated
  using (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and public.has_project_permission('transmittal.create', t.project_id)
  ));

-- Comment for operators
comment on function public.can_access_project(uuid) is
  'Phase 2: org-wide via project.read_all; else PM assignment, active membership, or exact project-scoped project.read. Org-scoped project.read alone is insufficient.';

comment on function public.protect_issued_transmittal_items() is
  'Blocks INSERT/UPDATE/DELETE on items when parent transmittal status = issued. Service-role JWT may bypass for ops/fixture cleanup only.';
