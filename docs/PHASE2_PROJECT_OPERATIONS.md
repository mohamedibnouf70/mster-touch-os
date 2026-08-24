# Phase 2 — Project Operations, Engineering & Document Control

## Goal

Operational engineering/document-control lifecycle on top of Phase 1:

Prepare → Internal review → Document Control → Formal submission → A–E decision → Revision → Approved for execution → Inspection/NCR → Closeout.

## What was added

### Schema (migrations 015–029)

- Engineering disciplines + project activation
- Controlled document numbering (`generate_document_number`)
- Document register extensions (type, discipline, SLA dates, decisions)
- RFI, Material Submittals, Shop Drawings, Method Statements
- Inspection Requests, NCR
- Project reports, correspondence
- Project contacts, transmittals (immutable when issued)
- Phase 2 RBAC + `project.read_all`
- Tightened `can_access_project` (membership / PM / read_all)
- RPCs: register, revise, apply A–E, issue transmittal, compute health
- Seeded versioned workflows for RFI/MAT/SHD/MS
- R00 version rows on register + revision (029)

### Application

- `/engineering` — RFI / MAT / SHD / MS / IR / NCR modules + create/lifecycle actions
- `/document-control` — formal register, A–E decisions, revisions, transmittals
- `/search` — database-side document number/title search
- Project detail tabs: engineering, RFI, submittals, shop drawings, inspections, NCR, reports, correspondence
- My Actions: overdue RFIs, NCRs, C/D revisions, inspections (sorted overdue → priority)
- Domain helpers: numbering, revision, health, execution eligibility
- Use cases: `src/server/use-cases/engineering.ts`

## Apply migrations

```bash
# Set DATABASE_URL to the Supabase Postgres connection string, then:
npm run db:apply-phase2
npm run verify:schema
npm run test:live
```

## Project health (deterministic)

| Level | Rule |
| --- | --- |
| RED | Critical open NCR **or** overdue RFI ≥ 5 **or** failed IR ≥ 3 |
| AMBER | Open NCR / overdue RFI or approvals / late stages / resubmit / failed IR |
| GREEN | Otherwise |

## Project-scoped access

Engineers with org-scoped `project.read` no longer see all projects. Access requires:

- `project.read_all`, or
- project-scoped role grant, or
- being project manager / active `project_members`

## Apply migrations

```bash
# Apply 015 → 028 after 001–014
supabase db push
# or run SQL files in order
npm run verify:schema
npm run test:live
```

## Not in Phase 2

Procurement, finance, HR, WhatsApp, email automation, AI, external portals.
