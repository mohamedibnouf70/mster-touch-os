# Phase 3 — Commercial, Procurement & Project Finance

## Scope

Project commercial control (not full accounting ERP):

- Suppliers & categories
- Project budgets & cost categories
- Purchase Requests → RFQ → Quotations → Comparison → PO
- Goods receipts, supplier invoices & payments
- Client contracts, milestones, valuations, invoices & receipts
- Variations (VO)
- Deterministic commercial health & cash-flow foundation

## Migrations

`031`–`045` (after `030`).

Apply: `supabase/phase3_apply_all.sql`

## Access model

Every commercial table requires:

1. `can_access_project(project_id)` (030 rules)
2. Module permission via `has_project_permission(key, project_id)`

Finance-sensitive fields (IBAN) via `get_supplier_banking()` RPC only.

Engineers may create PRs on assigned projects but do **not** receive finance.read by default.

## Numbering

- Suppliers: `SUP-####` via `generate_supplier_code`
- Project commercial docs: `MT-{PROJECT}-{TYPE}-{####}` via `generate_commercial_number`

## Health

`compute_project_commercial_health` — RED/AMBER/GREEN rules documented in migration `044` comment.

## Placeholders requiring admin confirmation

- VAT rate seed (15%)
- Approval threshold rules in `approval_threshold_rules`
