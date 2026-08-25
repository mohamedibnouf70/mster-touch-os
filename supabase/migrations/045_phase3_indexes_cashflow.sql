-- Master Touch OS — 045
-- Phase 3 indexes + search trigrams + cashflow helper view.

create extension if not exists pg_trgm;

create index if not exists suppliers_code_trgm_idx
  on public.suppliers using gin (supplier_code gin_trgm_ops);
create index if not exists suppliers_legal_trgm_idx
  on public.suppliers using gin (legal_name gin_trgm_ops);

create index if not exists purchase_requests_number_trgm_idx
  on public.purchase_requests using gin (pr_number gin_trgm_ops);
create index if not exists rfqs_number_trgm_idx
  on public.rfqs using gin (rfq_number gin_trgm_ops);
create index if not exists purchase_orders_number_trgm_idx
  on public.purchase_orders using gin (po_number gin_trgm_ops);
create index if not exists supplier_invoices_number_trgm_idx
  on public.supplier_invoices using gin (invoice_number gin_trgm_ops);
create index if not exists client_invoices_number_trgm_idx
  on public.client_invoices using gin (invoice_number gin_trgm_ops);
create index if not exists client_valuations_number_trgm_idx
  on public.client_valuations using gin (valuation_number gin_trgm_ops);
create index if not exists variations_number_trgm_idx
  on public.variations using gin (vo_number gin_trgm_ops);

-- Simple cash-flow period foundation (expected inflows/outflows by due date)
create or replace view public.project_cashflow_items as
select
  si.organization_id,
  si.project_id,
  'outflow'::text as direction,
  'supplier_invoice'::text as source_type,
  si.id as source_id,
  si.due_date as period_date,
  (si.total - coalesce((
    select sum(sp.amount) from public.supplier_payments sp where sp.supplier_invoice_id = si.id
  ), 0)) as amount,
  si.currency
from public.supplier_invoices si
where si.status not in ('paid', 'cancelled', 'rejected')
  and si.due_date is not null

union all

select
  ci.organization_id,
  ci.project_id,
  'inflow'::text,
  'client_invoice'::text,
  ci.id,
  ci.due_date,
  (ci.total - coalesce((
    select sum(cp.amount) from public.client_payments cp where cp.client_invoice_id = ci.id
  ), 0)),
  ci.currency
from public.client_invoices ci
where ci.status in ('issued', 'partially_paid', 'overdue')
  and ci.due_date is not null;

comment on view public.project_cashflow_items is
  'Foundation cash-flow lines from open supplier AP and client AR due dates. Not corporate treasury.';
