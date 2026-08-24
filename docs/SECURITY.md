# Security

## Non-negotiables

- Never expose `SUPABASE_SERVICE_ROLE_KEY` to the browser.
- Service role only in server modules marked `server-only` (`src/lib/supabase/admin.ts`).
- RLS enabled on all business-critical tables.
- Authorization checked in use cases **and** database helpers/RPCs.
- Private storage bucket; signed URLs only; no permanent public document URLs.
- Validate uploads: MIME allow-list + max size in `StorageService`.
- Never trust client-supplied organization/user ids for ownership; derive from session.
- Soft-deactivate users; do not erase audit/approval history.
- Audit logs are append-oriented for normal application roles.

## Session & CSRF

- Supabase SSR cookie session via `@supabase/ssr`.
- Mutations use Server Actions (same-origin cookie session).

## Helpers (PostgreSQL)

- `current_profile_id()`
- `current_organization_id()`
- `is_active_profile()` / `is_organization_member()`
- `has_permission(key, org, scope_type, scope_id)`
- `can_access_project(project_id)`
- `is_platform_admin()`

Security-definer helpers read auth tables carefully to avoid recursive RLS.

## Application errors

Typed errors (`Unauthorized`, `Forbidden`, `ValidationError`, `NotFound`, `Conflict`, `DatabaseError`) map to Arabic-friendly messages; raw DB errors are not shown to end users.

## Phase 2 notes

- `project.read_all` grants organization-wide project visibility (GM / Ops / DC / Quality / Super Admin).
- Engineers require **active project membership**, **PM assignment**, or an **exact** `user_roles` row with `scope_type = project` — org-scoped `project.read` alone is insufficient (`can_access_project` fixed in migration **030**).
- Root cause of prior leak: `has_permission()` treats organization-scoped grants as a wildcard for any requested scope; migration 026’s `has_permission('project.read', …, 'project', id)` still matched org-scoped Engineers.
- Issued transmittals and their items are immutable via BEFORE triggers (migration **030**). Authenticated updates raise; service-role may bypass for ops/fixture cleanup only.
- Shop drawing “approved for execution” requires official decision A/B and non-superseded status.

## Checklist (Phase 1)

- [x] No service role in client bundles
- [x] Server-side `authorize`
- [x] RLS policies + helpers
- [x] Signed storage URLs
- [x] Env validation (`src/lib/env.ts`)
- [x] Immutable-style audit inserts
- [ ] Production secrets rotation / monitoring (ops)
- [ ] Penetration test before Phase 10 launch
