# Suppliers

Table: `suppliers`, `supplier_contacts`, `supplier_categories`.

Code: `SUP-####` via `generate_supplier_code` (concurrency-safe counter).

Sensitive fields (`iban`, `bank_name`): use `get_supplier_banking(supplier_id)` — requires `supplier.manage` or `finance.read/manage`.

Statuses: ACTIVE, SUSPENDED, BLOCKED, ARCHIVED.
