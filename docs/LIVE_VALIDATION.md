# Live Supabase Validation (Phase 1.1)

## Prerequisites

1. Supabase project with migrations `001`–`014` applied in order.
2. Copy `.env.example` → `.env.local` and set:

```env
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
LIVE_TEST_ENABLED=true
```

3. Never commit `.env.local`.

## Commands

```bash
# Unit tests only (fast, no database)
npm test

# Schema table/bucket verification
npm run verify:schema

# Full live RLS/security matrix (creates ephemeral users, cleans up)
npm run test:live

# Everything
npm run test:all
npm run typecheck
npm run lint
npm run build
```

## What live tests cover

- Schema presence (tables, private `documents` bucket)
- Unauthenticated denial
- Cross-organization isolation
- RBAC / project membership
- Concurrent project code generation (`MT-PRJ-####`)
- Approval assignee enforcement + duplicate rejection
- SLA overdue query foundation
- Notification recipient scoping
- Employee deactivation (soft, history preserved)
- Audit log append-only behavior

## Bootstrap admin

Set `BOOTSTRAP_ADMIN_EMAIL` to the first admin's email. On login, if no platform admin exists, `bootstrap_platform_admin` RPC runs server-side via service role. Safe to rerun — returns `CONFLICT` when admin already exists.

## Proxy migration

Next.js 16 uses `src/proxy.ts` (replaces deprecated `middleware.ts`). Auth session refresh behavior is unchanged.
