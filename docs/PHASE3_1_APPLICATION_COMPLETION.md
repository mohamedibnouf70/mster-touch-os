# Phase 3.1 — Commercial Application Completion

## Status

**Database live gate:** PASS (031–046)  
**Application layer:** IN PROGRESS — Wave 1 foundation started

Phase 3 is **not GO** until all acceptance criteria in the Phase 3.1 spec are met end-to-end in UI + E2E.

## Wave 1 (started)

### Infrastructure
- `CommercialRepository` — paginated lists, detail fetches, dashboard stats, audit/approval helpers
- Shared UI: `RegisterTable`, `RegisterPagination`, `CommercialStatusBadge`, `MoneyDisplay`
- `entity-routes.ts` — deep links for My Actions / search

### Use-cases
- **procurement.ts** — PR approval submit, RFQ from PR, issue RFQ, quotation capture, award recommendation, PO from quotation, issue PO, post GRN
- **finance.ts** — supplier invoice create + match, approve for payment, record payment (RPC), variation approve, client valuation, client payment

### Routes (partial)
- `/procurement/purchase-requests` — list + filters + pagination
- `/procurement/purchase-requests/[id]` — detail, items, submit approval, convert to RFQ, activity

## Remaining (Wave 2+)

See implementation order in repo plan. Priority:

1. RFQ list/detail/issue/invitations/quotation/comparison
2. PO list/detail/approve/issue/print + delivery status
3. Goods receipts CRUD + post
4. Supplier invoices + payment UI
5. Suppliers management + performance
6. Finance dashboard completion
7. Client contract/milestones/valuations/invoices
8. Variations + project commercial tab (summary, cash flow, health)
9. Search + My Actions + CSV export
10. Playwright E2E (4 scenarios)
11. Integration tests

## Schema gaps

None identified requiring migration 047 yet. RFQ issue and PO creation are app-layer transactions against existing tables/RPCs.

## E2E strategy

Add `@playwright/test` with fixtures mirroring live-test pattern (prefixed users, service-role setup only). Scenarios 1–4 from Phase 3.1 spec. Document in `COMMERCIAL_E2E.md`.
