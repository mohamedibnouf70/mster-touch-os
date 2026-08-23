# RBAC

## Principles

1. Permissions are `resource.action` keys stored in PostgreSQL.
2. Roles map to permissions via `role_permissions`.
3. Users receive roles via `user_roles` with optional scope (`organization` | `department` | `project`).
4. External roles (`client`, `consultant`, `supplier`, `subcontractor`) never receive internal company access.
5. Frontend checks are UX only. Enforcement is:
   - Application: `authorize()` / `hasPermission()` / `can()`
   - Database: `has_permission(...)` inside RLS and RPCs

## Application API

```ts
can(grants, permission, { organizationId, projectId?, departmentId? })
authorize(ctx, permission, context?) // throws ForbiddenError
hasPermission(ctx, permission, context?)
```

Platform admins (`profiles.is_platform_admin`) bypass for bootstrap/ops only.

## Seeded internal roles

Super Admin, General Manager, Operations Manager, Department Manager, Project Manager, Project Engineer, Engineer, Document Controller, Finance Manager/Officer, HR Manager/Officer, Procurement Manager/Officer, HSE Manager/Officer, Quality Manager/Officer, Viewer.

## Permission catalog (Phase 1)

Includes (non-exhaustive): `project.*`, `user.*`, `document.*`, `approval.*`, `employee.*`, `finance.read|manage`, `audit.read`, `workflow.*`, `settings.manage`, `notification.read`, `reports.management.read`, `department.*`, `organization.*`, `role.*`.

See `src/lib/permissions/catalog.ts` and migration `013_seed_system.sql`.

## Contextual access

Architecture supports project-scoped grants so a Project Manager can later be limited to assigned projects. Phase 1 RLS also allows access when the user is project manager or active `project_members` entry (`can_access_project`).

## Deactivation

Setting `profiles.is_active = false` (and membership status) blocks access while preserving historical rows. Do not hard-delete employees for access control.
