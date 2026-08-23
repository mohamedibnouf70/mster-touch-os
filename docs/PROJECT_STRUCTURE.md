# Project structure

```text
src/
  app/                      # Next.js App Router (Arabic RTL shell)
    (app)/                  # Authenticated application
      page.tsx              # Dashboard
      projects/             # List, create, detail tabs
      approvals/
      documents/
      employees/
      departments/
      notifications/
      settings/
    login/
    auth/callback/
  components/
    layout/                 # App shell, sidebar
    auth/
    ui/                     # Shared primitives
  modules/                  # Domain Zod schemas (+ future module UI)
    auth|projects|users|approvals|documents/
  server/
    context.ts              # Auth + org + grants
    policies/authorize.ts
    domain/                 # Pure workflow & approval engines
    repositories/
    services/               # audit, events, notifications, storage
    use-cases/              # Server Actions
  lib/
    supabase/               # browser, server, middleware, admin
    permissions/
    errors|logger|env|i18n|events|utils/
  types/
supabase/migrations/        # Ordered SQL migrations
docs/                       # Architecture documentation
```

## Path alias

`@/*` → `src/*`
