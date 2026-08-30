# Master Touch OS — V1.0 Delivery & Operational Guide

## 1. Version & Release Overview
- **Product:** Master Touch OS (Enterprise Contracting & Project Resource Platform)
- **Release Version:** `v1.0.0-rc1` (Initial Client Delivery)
- **Target Audience:** Executive Leadership, Project Managers, Engineering, Finance, and Human Resources.

---

## 2. Included Production Modules (V1.0)

1. **Identity, Organization & Security Core**
   - Multi-tenant tenant isolation (`organizations`, `organization_members`).
   - Granular RBAC permissions (`permissions`, `roles`, `user_roles`).
   - Multi-tier Row-Level Security (RLS) deny-by-default architecture.
   - Comprehensive system audit logs and domain event bus.

2. **Organization Structure & Employee Master Data**
   - Department hierarchy management with parent/child tree representation.
   - Employee directory with Arabic/English profiles and employment status.
   - Employee compliance tracking (Iqama, Passport, GOSI, Insurance, Work Permit).
   - Structured HR alert hooks for document and probation expiries.

3. **Contracts, Versioned Compensation & HR Private Documents**
   - Immutable employment contracts with formal activation RPC.
   - Versioned compensation history with automated overlap prevention and date boundaries.
   - Secure HR private document vault with category-scoped RLS policies.
   - Masked employee banking summary with dedicated authorized RPC for payroll/finance.

4. **Project Management & Engineering Document Control**
   - Project lifecycle stages, project member access control, and discipline management.
   - Structured document numbering counters and revision control.
   - Technical submittals: Requests for Information (RFIs), Shop Drawings, Material Submittals, Method Statements, Inspection Requests, and Non-Conformance Reports (NCRs).

5. **Multi-Stage Workflow & Approval Engine**
   - Configurable multi-step approval workflows with conditional branching and delegation.
   - Approval audit tracking, status transitions, and real-time notifications.

6. **Procurement & Supply Chain**
   - Purchase Requests (PRs) with line items and workflow approvals.
   - Requests for Quotations (RFQs) with vendor bid comparison matrix.
   - Purchase Orders (POs) with immutable commercial terms upon issuance.
   - Partial and final Goods Receipt Notes (GRNs) with inventory balance updates.
   - Supplier Invoices, 3-way matching validation, and payment recording.

7. **Client Commercial & Revenue Lifecycle**
   - Project commercial client contracts and payment milestone schedules.
   - Client Valuations (internal review cycle, client submission, partial certifications).
   - Client Invoicing and accounts receivable receipt tracking.
   - Variation Orders (VOs) with contract value revision recalculations.

---

## 3. Production Architecture

```
                               ┌────────────────────────────────┐
                               │   Client Web Browser / Mobile  │
                               └───────────────┬────────────────┘
                                               │ HTTPS (TLS 1.3)
                                               ▼
                               ┌────────────────────────────────┐
                               │     Next.js 16 (App Router)    │
                               │     Turbopack Production Engine │
                               └───────────────┬────────────────┘
                                               │
               ┌───────────────────────────────┴───────────────────────────────┐
               ▼                                                               ▼
┌───────────────────────────────┐                               ┌───────────────────────────────┐
│     Supabase / PostgreSQL     │                               │      Private Storage Bucket   │
│  - 55 Additive Migrations     │                               │  - Path: org/{id}/hr/...      │
│  - Row-Level Security (RLS)   │                               │  - Signed URL Generator       │
│  - SECURITY DEFINER RPCs      │                               │  - Document Versioning        │
└───────────────────────────────┘                               └───────────────────────────────┘
```

---

## 4. Role & Access Control Summary

| Role | Operational Scope & Permissions |
|---|---|
| **Super Admin** | Full multi-tenant configuration, system seeds, and administrative control. |
| **General / Ops Manager** | Project oversight, workflow approvals, organizational dashboard reviews. |
| **HR Manager** | Employee master onboarding, department trees, contracts, compensation, HR documents, bank management. |
| **HR Officer** | Employee directory, compliance oversight, operational document handling (no compensation edit). |
| **Finance Manager** | Commercial contracts, valuations, client/supplier invoicing, payment recording, payroll bank read. |
| **Project Manager** | Project management, PR submission, submittal approvals, site coordination. |
| **Project / Site Engineer** | Engineering submittals, RFIs, shop drawings, technical submittals, own profile read (strictly denied financial/HR private data). |
| **Employee (Self-Service)** | Read own profile, own active contract summary, own compliance, masked banking summary. |

---

## 5. Deployment & Runtime Requirements

### Required Environment Variables (Names Only)
- `NEXT_PUBLIC_SUPABASE_URL` — Supabase project API gateway endpoint.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — Client-side anonymous Supabase public key.
- `SUPABASE_SERVICE_ROLE_KEY` — Server-only private key for backend administrative tasks.
- `E2E_BASE_URL` — (Optional / CI) Target URL for end-to-end verification.
- `E2E_PASSWORD` / `LIVE_TEST_PASSWORD_PREFIX` — (Test harness only) Deterministic credential prefixes.

### Supabase & Storage Configuration
- PostgreSQL instance running Supabase Extensions (`uuid-ossp`, `pgcrypto`).
- Migrations `001` through `055` executed in sequential order.
- Private storage bucket `documents` provisioned with RLS enabled.

---

## 6. How to Run, Build & Test

### Local Development
```bash
npm install
npm run dev
# Starts local development server on http://localhost:3000
```

### Production Build & Launch
```bash
npm run build
npm run start
# Runs optimized production build on port 3000
```

### Quality Assurance & Automated Test Gates
```bash
# Unit test suite (Domain helpers, schemas, calculations)
npm test

# Remote Live Database test suite (RLS, stored procedures, isolation)
npm run test:live

# Full End-to-End Suite (Playwright against production build)
npm run test:e2e

# TypeScript static typecheck
npm run typecheck

# Code quality and styling lint
npm run lint
```

---

## 7. Known Limitations & Post-V1 Roadmap
See `docs/KNOWN_LIMITATIONS_V1.md` for deferred features scheduled for subsequent releases.
