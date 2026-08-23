# Workflow Engine

## Goals

Reusable, versioned workflows for projects and future modules (documents, procurement, HR, etc.).

## Versioning rule

A published workflow version bound to running/historical instances must **not** be silently mutated. Changes require a new `workflow_versions` row; new instances bind to a specific version id.

## Concepts

| Concept | Table |
| --- | --- |
| Definition | `workflow_definitions` |
| Immutable snapshot | `workflow_versions` |
| Step template | `workflow_steps` (+ rules) |
| Runtime | `workflow_instances` |
| Runtime steps | `workflow_instance_steps` |

Step assignment types: user, role, department, project_manager, unassigned.

Optional per step: approval requirement, SLA duration, escalation, required documents, reject/resubmit target keys, automatic actions (hooks for later).

## Instance lifecycle

Workflow status: `pending` → `in_progress` → `completed` | `cancelled`

Step status: `pending` | `ready` | `in_progress` | `completed` | `skipped` | `rejected` | `cancelled`

Pure transition logic lives in `src/server/domain/workflow.ts` and is mirrored by RPC `complete_workflow_step` for concurrency safety (prevents double-completion).

## Outcomes

- `complete` — advance to next sequential ready step or finish instance
- `reject` — follow `on_reject_step_key` or cancel remaining
- `resubmit` — follow `on_resubmit_step_key`

## Relationship to approvals

Workflow execution status ≠ approval decision. When a step requires approval, the approval engine records official codes A–E separately.

## Starting instances

RPC / use case `start_workflow` binds `workflow_version_id` and materializes instance steps. Duplicate starts for the same entity+definition should be guarded at the application/RPC layer.
