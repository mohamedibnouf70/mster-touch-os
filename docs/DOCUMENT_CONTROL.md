# Document Control

## Register spine

Controlled artifacts live in `documents` (`is_register_controlled = true`) with:

- `document_number` (unique per org)
- `type_code` → `document_type_codes`
- `discipline_id`
- `current_revision` (R00+)
- `official_decision` (A–E)
- `submission_status`, SLA timestamps
- optional `workflow_instance_id` / `approval_request_id`

Type-specific tables (`rfis`, `material_submittals`, …) FK to `documents`.

## Revisions

- Append-only `document_versions`
- One `is_current = true` per document
- Prior versions: `is_superseded = true`
- RPC `create_document_revision` advances R00→R01… and supersedes current

## Numbering

See [DOCUMENT_NUMBERING.md](./DOCUMENT_NUMBERING.md).

## UI

`/document-control` — filters, overdue, A–E decisions, create next revision on C/D.
