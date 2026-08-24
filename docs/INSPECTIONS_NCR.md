# Inspections & NCR

## Inspection Requests

Statuses include `failed` and `reinspection_required`. Failed IR can link to NCR via `related_ncr_id` / `parent_inspection_id`.

## NCR

Severities: low / medium / high / **critical**.

Closing requires `verification` + `verified_by`.

Critical NCR emits `ncr.critical` and a high-priority in-app notification.
