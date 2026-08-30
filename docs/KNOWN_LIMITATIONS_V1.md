# Master Touch OS — V1.0 Known Limitations & Post-V1 Roadmap

---

## 1. Scope & Delivery Intent

The V1.0 release candidate of **Master Touch OS** is focused on delivering a stable, production-grade core for **Project Document Control, Supply Chain & Procurement, Client Commercial Revenue, and Employee Master Data / HR Baseline**.

The items below are **explicitly deferred post-V1 roadmap capabilities** that are designed to build upon the established V1.0 foundational data models and security boundaries.

---

## 2. Deferred Post-V1 Modules & Capabilities

### A. Human Resources & Payroll (Phases 4.3 – 4.6)
1. **Automated Payroll Engine & Runs (Phase 4.4)**
   - *Status in V1:* Base versioned compensation (`employee_compensation_versions`) and banking (`employee_bank_accounts`) data models are live and ready.
   - *Post-V1:* Batch monthly payroll calculations, deductions/overtime processors, WPS file generation, and payment slip dispatch.
2. **Leave Management & Balances (Phase 4.3)**
   - *Status in V1:* Prepared in HR architecture; leave tables and request flows are deferred.
   - *Post-V1:* Annual leave accrual calculators, leave request approvals, balance ledger, and leave-calendar integration.
3. **Attendance & Time Tracking (Phase 4.3)**
   - *Status in V1:* Deferred.
   - *Post-V1:* Daily check-in/out logs, biometric device sync, timesheet reconciliation.
4. **Saudi Statutory Labor Calculations (Phase 4.5)**
   - *Status in V1:* Compliance dates and document expiries are tracked.
   - *Post-V1:* Automated End-of-Service (EOS) award calculations and General Organization for Social Insurance (GOSI) contribution formulas.
5. **Employee Expense Claims & Reimbursements**
   - *Status in V1:* Deferred.
   - *Post-V1:* Expense submission, receipt attachment, manager approval, and finance reimbursement batching.
6. **Offboarding & Exit Workflows**
   - *Status in V1:* Safe deactivation preserves complete historical records.
   - *Post-V1:* Formal clearance workflows, asset return checklists, and exit interview logs.

---

### B. Intelligent Automation & Integrations (Phases 5.x)
1. **AI Manager Assistant / Generative Insights**
   - *Status in V1:* Not included.
   - *Post-V1:* Natural language document queries, automated submittal summaries, and risk forecasting.
2. **External Messaging / WhatsApp / SMS Notifications**
   - *Status in V1:* System in-app notification center and domain events are active.
   - *Post-V1:* Direct WhatsApp Business API and SMS gateway dispatch for urgent approval alerts.
3. **Advanced Executive BI & Predictive Analytics**
   - *Status in V1:* High-performance operational counts and real-time entity status summaries are active.
   - *Post-V1:* Multi-project cash-flow forecasting, earned value management (EVM), and predictive procurement timeline analytics.

---

## 3. Post-V1 Technical Hardening Notes

1. **Banking Concurrency Partial Index:**
   - *Current Implementation:* Primary bank account uniqueness is serialized at the transactional RPC layer via `upsert_employee_banking` and `deactivate_employee_bank_account`.
   - *Post-V1 Hardening:* Add an explicit partial unique index on `employee_bank_accounts (employee_id) WHERE (is_primary = true AND is_active = true)`.
