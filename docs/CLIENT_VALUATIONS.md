# Client Valuations

Tables: `client_valuations`, `client_invoices`, `client_payments`, `project_contracts`, `contract_milestones`.

Valuation preserves history; certified amount may differ from claim.

Outstanding receivables derived from invoice totals minus client payments (not stored totals).

Statuses documented in migration `040_client_valuations.sql`.
