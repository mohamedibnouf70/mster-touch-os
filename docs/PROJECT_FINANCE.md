# Project Finance

Routes: `/finance`, project tab **Commercial**.

Modules: budgets, supplier AP, client AR, valuations, variations, cash-flow view.

Summary RPC: `compute_project_commercial_summary(project_id)` — requires `finance.read` or `commercial_reports.read`.

Health RPC: `compute_project_commercial_health(project_id)`.

Not a GL — operational control only.
