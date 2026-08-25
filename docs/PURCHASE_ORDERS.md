# Purchase Orders

Issued POs are **immutable** (triggers on header/items). Use amendment/versioning in future phases for changes.

Issue RPC: `issue_purchase_order(po_id)` — sets `ordered_quantity`, status `issued`.

Commitment: approved/issued PO totals feed `committed_cost` in commercial summary.

Three-way match foundation: PO ↔ goods receipt ↔ supplier invoice (`evaluate_supplier_invoice_match`).
