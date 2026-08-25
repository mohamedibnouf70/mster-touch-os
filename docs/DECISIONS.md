# Architectural decisions

## ADR-001 — Supabase + Next.js Server Actions

**Decision:** Use Supabase Auth/Postgres/Storage with Next.js Server Actions and selective RPCs.

**Why:** Fast path to RLS, auth, and storage while keeping business mutations on the server. Atomic numbering/approvals/workflows use PostgreSQL functions.

## ADR-002 — Versioned workflows

**Decision:** Bind instances to `workflow_versions`, never mutate published history in place.

**Why:** Historical projects must remain explainable for audit and future AI.

## ADR-003 — Separate approval decisions from workflow status

**Decision:** Official codes A–E live on approval actions; workflow has its own status enum.

**Why:** Contracting document control language differs from process engine states.

## ADR-004 — Profiles vs employees

**Decision:** `profiles` = auth-linked identity; `employees` = employment record.

**Why:** External users (later portals) may have profiles without employees; salary/iqama never in auth metadata.

## ADR-005 — Collapsed Phase 1 repositories

**Decision:** One `CoreRepository` + `platform` use-case module for Phase 1.

**Why:** Avoid empty module sprawl; extract per-module services when Phase 2+ grows.

## ADR-006 — UTC storage, Riyadh display

**Decision:** Store timestamps in UTC; organization timezone `Asia/Riyadh` for business display/SLA messaging.

**Why:** Consistent official clocks independent of client device timezone.

## ADR-007 — No AI/WhatsApp in Phase 1

**Decision:** Schema + event/notification abstractions only.

**Why:** Keep source of truth structured; integrations must plug into channels/events later without rewrite.

## ADR-008 — Soft deactivation over hard delete

**Decision:** `is_active` / membership status / `archived_at`.

**Why:** Preserve auditability and AI-explainable history.

## ADR-009 — Project commercial control without GL (Phase 3)

**Decision:** Operational procurement/finance tables + derived summaries; no general ledger or double-entry.

**Why:** Master Touch needs project cost/commitment/AP/AR control first; statutory accounting belongs to a later phase or external ERP.

## ADR-010 — Issued commercial document immutability

**Decision:** PO/valuation/invoice/payment history protected by triggers; changes via status transitions or future amendment records.

**Why:** Financial audit trail and AI explainability require stable issued records.
