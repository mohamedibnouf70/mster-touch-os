# RFI

Statuses: `draft` → `internal_review` → `submitted` → `under_review` → `answered` → `closed` (`cancelled`).

Rules:

- Question text is preserved; response is additive
- Closed/cancelled RFIs cannot silently rewrite question/response (DB trigger)
- Overdue = `response_required_by < now()` while submitted/under_review

Create via `createRfiAction` → `register_controlled_document` + `rfis` row.
