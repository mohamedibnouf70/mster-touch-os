# Master Touch OS — Architecture

## Product model

```text
Company → Department → User → Role → Project → Stage → Workflow → Task/Document → Approval → SLA → Escalation → Audit Log
```

Later layers (not Phase 1):

```text
Operational Data → Rules Engine → Risk Engine → AI Analysis → Management Alerts
```

## Layering

```text
UI (App Router / Server Components)
  → Server Actions / Use Cases
    → Policies (authorize / can)
      → Domain (pure transition logic)
      → Services (audit, events, notifications, storage)
      → Repositories
        → Supabase / PostgreSQL (+ RLS)
```

Rules:

- Business logic does **not** live in React components.
- UI never decides sensitive authorization alone; server + RLS always enforce.
- Repositories own data access; UI does not call Supabase for mutations of business entities except through use cases.
- Domain packages (`workflow`, `approval`) are pure TypeScript and unit-testable without a database.

## Runtime stack

| Layer | Choice |
| --- | --- |
| Frontend | Next.js 16 App Router, React 19, TypeScript strict, Tailwind CSS v4 |
| Forms | React Hook Form + Zod (where interactive); Server Actions + Zod for mutations |
| Backend | Next.js Server Actions + PostgreSQL RPC for atomic operations |
| Auth / DB / Storage | Supabase Auth, PostgreSQL, private Storage buckets |
| Timezone / currency | `Asia/Riyadh` / `SAR` as organization defaults; timestamps stored in UTC |

## Multi-tenancy

- Every business row carries `organization_id`.
- Membership is modeled via `organization_members`.
- Session context resolves the active organization from membership (Phase 1: first active membership).
- RLS helpers (`is_organization_member`, `has_permission`, `can_access_project`) prevent cross-tenant reads/writes.

## Structure deviation (documented)

Suggested module-local repositories were collapsed into:

- `src/server/repositories/core.repository.ts` — read models for Phase 1 surfaces
- `src/server/use-cases/platform.ts` — mutation orchestration
- `src/modules/*/schemas.ts` — Zod contracts per domain

**Reason:** Phase 1 surface area is cohesive; splitting into many empty module folders would add noise without clearer boundaries. Module folders remain the extension point for Phase 2+ (finance, HR, etc.). When a module exceeds ~3 use cases or needs distinct repositories, extract it from `platform.ts` / `core.repository.ts`.

## Arabic-first UI

- Root layout: `lang="ar"` `dir="rtl"`.
- Copy defaults Arabic; English fields exist on entities (`*_en`) for bilingual records.
- Locale on profiles (`ar` | `en`) prepares future UI language switching without schema rewrite.

## Event readiness

`EventService` publishes domain events into `domain_events` (and can fan out synchronously today). Future workers can poll / subscribe without changing producers:

`Event → Rule → Condition → Action`
