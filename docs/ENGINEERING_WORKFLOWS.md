# Engineering Workflows

Versioned workflows (Phase 1 engine). Seeded in migration `028_phase2_indexes_workflows.sql`:

| Code | Entity | Definition UUID |
| --- | --- | --- |
| `document_approval` | document (Phase 1) | `40000000-0000-0000-0000-000000000001` |
| `rfi_lifecycle` | RFI | `40000000-0000-0000-0000-000000000010` |
| `submittal_lifecycle` | Material submittal | `40000000-0000-0000-0000-000000000002` |
| `shop_drawing_lifecycle` | Shop drawing | `40000000-0000-0000-0000-000000000003` |
| `method_statement_lifecycle` | Method statement (HSE + QA gates) | `40000000-0000-0000-0000-000000000004` |

Instances bind to a published `workflow_versions` row — historical runs are not mutated by later template edits.

Internal review → Document Control → external A–E decision uses existing approval RPCs + `apply_document_approval_decision`.
