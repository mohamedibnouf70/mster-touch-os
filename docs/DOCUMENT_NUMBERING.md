# Document Numbering

## Format

```text
MT-{PROJECT_CODE}-{TYPE}-{DISCIPLINE}-{SEQ4}-R{rev}
```

Example: `MT-PRJ-0001-RFI-ELEC-0001-R00`

## Concurrency

`document_number_counters` keyed by `(organization_id, project_id, type_code, discipline_code)`.

RPC `generate_document_number` uses `INSERT … ON CONFLICT DO UPDATE next_value = next_value + 1` (same pattern as project codes). **Never** `MAX()+1`.

## Registration

`register_controlled_document` allocates the number, creates the register row at **R00**, audits `document.registered`.
