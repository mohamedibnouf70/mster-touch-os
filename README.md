# Master Touch OS

Internal operating platform for **Master Touch** (Saudi contracting, interior design, MEP, smart systems, engineering, and project execution).

Phase 1 delivers the enterprise foundation: Auth, Organization, RBAC, Projects, Stages, Workflows, Approvals (A–E), Documents, Notifications, Audit, and Arabic-first UI.

## Stack

- Next.js 16 App Router + TypeScript strict
- Tailwind CSS v4
- Supabase (Auth, PostgreSQL + RLS, Storage)
- Zod validation
- Vitest for domain/RBAC tests

## Quick start

1. Copy `.env.example` to `.env.local` and fill Supabase keys.
2. Apply SQL migrations in `supabase/migrations/` in numeric order.
3. Install and run:

```bash
npm install
npm run dev
```

## Scripts

| Command | Purpose |
| --- | --- |
| `npm run dev` | Development server |
| `npm run build` | Production build |
| `npm run typecheck` | TypeScript |
| `npm run lint` | ESLint |
| `npm test` | Unit tests |

## Documentation

See `/docs`:

- [ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [DATABASE.md](docs/DATABASE.md)
- [RBAC.md](docs/RBAC.md)
- [WORKFLOW_ENGINE.md](docs/WORKFLOW_ENGINE.md)
- [SECURITY.md](docs/SECURITY.md)
- [PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)
- [PHASES.md](docs/PHASES.md)
- [DECISIONS.md](docs/DECISIONS.md)

## Security notes

- Never put `SUPABASE_SERVICE_ROLE_KEY` in client code.
- Authorization is enforced server-side and via RLS.
- Document storage is private; use signed URLs only.
