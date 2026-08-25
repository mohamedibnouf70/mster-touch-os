# Financial Security

## Two-layer access

1. `can_access_project(project_id)` — membership / PM / scoped role (030 rules).
2. `has_project_permission(key, project_id)` — module permission.

## Sensitive data

- Supplier IBAN/bank: `get_supplier_banking` RPC only.
- Commercial summary/margin: `finance.read` or `commercial_reports.read`.
- Engineers: PR create/read on assigned projects; **no default finance.read**.

## RLS

All Phase 3 business tables have RLS in `043_phase3_rls.sql`. Never trust client-supplied `organization_id`.

## Money

PostgreSQL `numeric(18,2)`; payment guard in `record_supplier_payment`.
