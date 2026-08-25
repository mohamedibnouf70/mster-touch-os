-- Master Touch OS — 043
-- Phase 3 RLS: project access AND commercial/finance permission.

alter table public.supplier_categories enable row level security;
alter table public.supplier_counters enable row level security;
alter table public.suppliers enable row level security;
alter table public.supplier_contacts enable row level security;
alter table public.vat_rate_configs enable row level security;
alter table public.cost_categories enable row level security;
alter table public.project_budgets enable row level security;
alter table public.project_budget_items enable row level security;
alter table public.commercial_number_counters enable row level security;
alter table public.purchase_requests enable row level security;
alter table public.purchase_request_items enable row level security;
alter table public.rfqs enable row level security;
alter table public.rfq_items enable row level security;
alter table public.rfq_suppliers enable row level security;
alter table public.supplier_quotations enable row level security;
alter table public.supplier_quotation_items enable row level security;
alter table public.quotation_comparisons enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;
alter table public.supplier_invoices enable row level security;
alter table public.supplier_invoice_items enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.project_contracts enable row level security;
alter table public.contract_milestones enable row level security;
alter table public.client_valuations enable row level security;
alter table public.client_invoices enable row level security;
alter table public.client_payments enable row level security;
alter table public.variations enable row level security;
alter table public.approval_threshold_rules enable row level security;

-- Supplier categories / cost categories / VAT: org members with supplier or finance read
drop policy if exists supplier_categories_select on public.supplier_categories;
create policy supplier_categories_select on public.supplier_categories
  for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists supplier_categories_write on public.supplier_categories;
create policy supplier_categories_write on public.supplier_categories
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

drop policy if exists cost_categories_select on public.cost_categories;
create policy cost_categories_select on public.cost_categories
  for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists cost_categories_write on public.cost_categories;
create policy cost_categories_write on public.cost_categories
  for all to authenticated
  using (public.has_permission('project_budget.manage', organization_id)
    or public.has_permission('finance.manage', organization_id))
  with check (public.has_permission('project_budget.manage', organization_id)
    or public.has_permission('finance.manage', organization_id));

drop policy if exists vat_rate_configs_select on public.vat_rate_configs;
create policy vat_rate_configs_select on public.vat_rate_configs
  for select to authenticated
  using (
    public.has_permission('finance.read', organization_id)
    or public.has_permission('procurement.read', organization_id)
  );

drop policy if exists vat_rate_configs_write on public.vat_rate_configs;
create policy vat_rate_configs_write on public.vat_rate_configs
  for all to authenticated
  using (public.has_permission('finance.manage', organization_id))
  with check (public.has_permission('finance.manage', organization_id));

-- Suppliers: non-sensitive columns via table; IBAN restricted by app views/RPC
drop policy if exists suppliers_select on public.suppliers;
create policy suppliers_select on public.suppliers
  for select to authenticated
  using (
    public.is_organization_member(organization_id)
    and public.has_permission('supplier.read', organization_id)
  );

drop policy if exists suppliers_write on public.suppliers;
create policy suppliers_write on public.suppliers
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

drop policy if exists supplier_contacts_select on public.supplier_contacts;
create policy supplier_contacts_select on public.supplier_contacts
  for select to authenticated
  using (
    public.is_organization_member(organization_id)
    and public.has_permission('supplier.read', organization_id)
  );

drop policy if exists supplier_contacts_write on public.supplier_contacts;
create policy supplier_contacts_write on public.supplier_contacts
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

drop policy if exists supplier_counters_all on public.supplier_counters;
create policy supplier_counters_all on public.supplier_counters
  for all to authenticated
  using (public.has_permission('supplier.manage', organization_id))
  with check (public.has_permission('supplier.manage', organization_id));

-- Helper macro pattern for project commercial tables
-- Budgets
drop policy if exists project_budgets_select on public.project_budgets;
create policy project_budgets_select on public.project_budgets
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('project_budget.read', project_id)
  );

drop policy if exists project_budgets_write on public.project_budgets;
create policy project_budgets_write on public.project_budgets
  for all to authenticated
  using (public.has_project_permission('project_budget.manage', project_id))
  with check (public.has_project_permission('project_budget.manage', project_id));

drop policy if exists project_budget_items_select on public.project_budget_items;
create policy project_budget_items_select on public.project_budget_items
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('project_budget.read', project_id)
  );

drop policy if exists project_budget_items_write on public.project_budget_items;
create policy project_budget_items_write on public.project_budget_items
  for all to authenticated
  using (public.has_project_permission('project_budget.manage', project_id))
  with check (public.has_project_permission('project_budget.manage', project_id));

-- Purchase requests
drop policy if exists purchase_requests_select on public.purchase_requests;
create policy purchase_requests_select on public.purchase_requests
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('purchase_request.read', project_id)
  );

drop policy if exists purchase_requests_insert on public.purchase_requests;
create policy purchase_requests_insert on public.purchase_requests
  for insert to authenticated
  with check (public.has_project_permission('purchase_request.create', project_id));

drop policy if exists purchase_requests_update on public.purchase_requests;
create policy purchase_requests_update on public.purchase_requests
  for update to authenticated
  using (
    public.has_project_permission('purchase_request.create', project_id)
    or public.has_project_permission('purchase_request.approve', project_id)
    or public.has_project_permission('procurement.manage', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists purchase_request_items_select on public.purchase_request_items;
create policy purchase_request_items_select on public.purchase_request_items
  for select to authenticated
  using (exists (
    select 1 from public.purchase_requests pr
    where pr.id = purchase_request_id
      and public.can_access_project(pr.project_id)
      and public.has_project_permission('purchase_request.read', pr.project_id)
  ));

drop policy if exists purchase_request_items_write on public.purchase_request_items;
create policy purchase_request_items_write on public.purchase_request_items
  for all to authenticated
  using (exists (
    select 1 from public.purchase_requests pr
    where pr.id = purchase_request_id
      and public.has_project_permission('purchase_request.create', pr.project_id)
  ))
  with check (exists (
    select 1 from public.purchase_requests pr
    where pr.id = purchase_request_id
      and public.has_project_permission('purchase_request.create', pr.project_id)
  ));

-- RFQ
drop policy if exists rfqs_select on public.rfqs;
create policy rfqs_select on public.rfqs
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('rfq.read', project_id));

drop policy if exists rfqs_insert on public.rfqs;
create policy rfqs_insert on public.rfqs
  for insert to authenticated
  with check (public.has_project_permission('rfq.create', project_id));

drop policy if exists rfqs_update on public.rfqs;
create policy rfqs_update on public.rfqs
  for update to authenticated
  using (
    public.has_project_permission('rfq.manage', project_id)
    or public.has_project_permission('rfq.issue', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists rfq_items_all on public.rfq_items;
create policy rfq_items_all on public.rfq_items
  for all to authenticated
  using (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and public.can_access_project(r.project_id)
      and public.has_project_permission('rfq.read', r.project_id)
  ))
  with check (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and public.has_project_permission('rfq.create', r.project_id)
  ));

drop policy if exists rfq_suppliers_all on public.rfq_suppliers;
create policy rfq_suppliers_all on public.rfq_suppliers
  for all to authenticated
  using (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and public.can_access_project(r.project_id)
      and public.has_project_permission('rfq.read', r.project_id)
  ))
  with check (exists (
    select 1 from public.rfqs r
    where r.id = rfq_id and (
      public.has_project_permission('rfq.issue', r.project_id)
      or public.has_project_permission('rfq.manage', r.project_id)
    )
  ));

-- Quotations
drop policy if exists supplier_quotations_select on public.supplier_quotations;
create policy supplier_quotations_select on public.supplier_quotations
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('quotation.read', project_id));

drop policy if exists supplier_quotations_write on public.supplier_quotations;
create policy supplier_quotations_write on public.supplier_quotations
  for all to authenticated
  using (
    public.has_project_permission('quotation.create', project_id)
    or public.has_project_permission('quotation.compare', project_id)
  )
  with check (public.has_project_permission('quotation.create', project_id));

drop policy if exists supplier_quotation_items_all on public.supplier_quotation_items;
create policy supplier_quotation_items_all on public.supplier_quotation_items
  for all to authenticated
  using (exists (
    select 1 from public.supplier_quotations q
    where q.id = quotation_id and public.can_access_project(q.project_id)
      and public.has_project_permission('quotation.read', q.project_id)
  ))
  with check (exists (
    select 1 from public.supplier_quotations q
    where q.id = quotation_id and public.has_project_permission('quotation.create', q.project_id)
  ));

drop policy if exists quotation_comparisons_all on public.quotation_comparisons;
create policy quotation_comparisons_all on public.quotation_comparisons
  for all to authenticated
  using (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('quotation.compare', project_id)
      or public.has_project_permission('quotation.recommend', project_id)
      or public.has_project_permission('quotation.read', project_id)
    )
  )
  with check (
    public.has_project_permission('quotation.compare', project_id)
    or public.has_project_permission('quotation.recommend', project_id)
  );

-- Purchase orders
drop policy if exists purchase_orders_select on public.purchase_orders;
create policy purchase_orders_select on public.purchase_orders
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('purchase_order.read', project_id));

drop policy if exists purchase_orders_insert on public.purchase_orders;
create policy purchase_orders_insert on public.purchase_orders
  for insert to authenticated
  with check (public.has_project_permission('purchase_order.create', project_id));

drop policy if exists purchase_orders_update on public.purchase_orders;
create policy purchase_orders_update on public.purchase_orders
  for update to authenticated
  using (
    public.has_project_permission('purchase_order.create', project_id)
    or public.has_project_permission('purchase_order.approve', project_id)
    or public.has_project_permission('purchase_order.issue', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists purchase_order_items_all on public.purchase_order_items;
create policy purchase_order_items_all on public.purchase_order_items
  for all to authenticated
  using (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.can_access_project(po.project_id)
      and public.has_project_permission('purchase_order.read', po.project_id)
  ))
  with check (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.has_project_permission('purchase_order.create', po.project_id)
  ));

-- Goods receipts
drop policy if exists goods_receipts_select on public.goods_receipts;
create policy goods_receipts_select on public.goods_receipts
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('goods_receipt.read', project_id));

drop policy if exists goods_receipts_write on public.goods_receipts;
create policy goods_receipts_write on public.goods_receipts
  for all to authenticated
  using (
    public.has_project_permission('goods_receipt.create', project_id)
    or public.has_project_permission('goods_receipt.manage', project_id)
  )
  with check (
    public.has_project_permission('goods_receipt.create', project_id)
    or public.has_project_permission('goods_receipt.manage', project_id)
  );

drop policy if exists goods_receipt_items_all on public.goods_receipt_items;
create policy goods_receipt_items_all on public.goods_receipt_items
  for all to authenticated
  using (exists (
    select 1 from public.goods_receipts g
    where g.id = goods_receipt_id
      and public.can_access_project(g.project_id)
      and public.has_project_permission('goods_receipt.read', g.project_id)
  ))
  with check (exists (
    select 1 from public.goods_receipts g
    where g.id = goods_receipt_id
      and public.has_project_permission('goods_receipt.create', g.project_id)
  ));

-- Supplier invoices / payments (finance-sensitive)
drop policy if exists supplier_invoices_select on public.supplier_invoices;
create policy supplier_invoices_select on public.supplier_invoices
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('supplier_invoice.read', project_id)
  );

drop policy if exists supplier_invoices_write on public.supplier_invoices;
create policy supplier_invoices_write on public.supplier_invoices
  for all to authenticated
  using (
    public.has_project_permission('supplier_invoice.create', project_id)
    or public.has_project_permission('supplier_invoice.review', project_id)
    or public.has_project_permission('supplier_invoice.approve', project_id)
  )
  with check (
    public.has_project_permission('supplier_invoice.create', project_id)
    or public.has_project_permission('supplier_invoice.review', project_id)
    or public.has_project_permission('supplier_invoice.approve', project_id)
  );

drop policy if exists supplier_invoice_items_all on public.supplier_invoice_items;
create policy supplier_invoice_items_all on public.supplier_invoice_items
  for all to authenticated
  using (exists (
    select 1 from public.supplier_invoices i
    where i.id = supplier_invoice_id
      and public.can_access_project(i.project_id)
      and public.has_project_permission('supplier_invoice.read', i.project_id)
  ))
  with check (exists (
    select 1 from public.supplier_invoices i
    where i.id = supplier_invoice_id
      and public.has_project_permission('supplier_invoice.create', i.project_id)
  ));

drop policy if exists supplier_payments_select on public.supplier_payments;
create policy supplier_payments_select on public.supplier_payments
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('supplier_payment.read', project_id)
  );

drop policy if exists supplier_payments_write on public.supplier_payments;
create policy supplier_payments_write on public.supplier_payments
  for all to authenticated
  using (
    public.has_project_permission('supplier_payment.record', project_id)
    or public.has_project_permission('supplier_payment.approve', project_id)
  )
  with check (public.has_project_permission('supplier_payment.record', project_id));

-- Contracts / valuations / client invoices / payments
drop policy if exists project_contracts_select on public.project_contracts;
create policy project_contracts_select on public.project_contracts
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('finance.read', project_id)
      or public.has_project_permission('client_valuation.read', project_id)
      or public.has_project_permission('commercial_reports.read', project_id)
      or public.has_project_permission('project_budget.read', project_id)
    )
  );

drop policy if exists project_contracts_write on public.project_contracts;
create policy project_contracts_write on public.project_contracts
  for all to authenticated
  using (public.has_project_permission('finance.manage', project_id))
  with check (public.has_project_permission('finance.manage', project_id));

drop policy if exists contract_milestones_all on public.contract_milestones;
create policy contract_milestones_all on public.contract_milestones
  for all to authenticated
  using (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('finance.read', project_id)
      or public.has_project_permission('client_valuation.read', project_id)
    )
  )
  with check (public.has_project_permission('finance.manage', project_id));

drop policy if exists client_valuations_select on public.client_valuations;
create policy client_valuations_select on public.client_valuations
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('client_valuation.read', project_id)
  );

drop policy if exists client_valuations_write on public.client_valuations;
create policy client_valuations_write on public.client_valuations
  for all to authenticated
  using (
    public.has_project_permission('client_valuation.create', project_id)
    or public.has_project_permission('client_valuation.submit', project_id)
    or public.has_project_permission('client_valuation.approve', project_id)
  )
  with check (
    public.has_project_permission('client_valuation.create', project_id)
    or public.has_project_permission('client_valuation.submit', project_id)
  );

drop policy if exists client_invoices_select on public.client_invoices;
create policy client_invoices_select on public.client_invoices
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('client_invoice.read', project_id)
  );

drop policy if exists client_invoices_write on public.client_invoices;
create policy client_invoices_write on public.client_invoices
  for all to authenticated
  using (
    public.has_project_permission('client_invoice.create', project_id)
    or public.has_project_permission('client_invoice.issue', project_id)
  )
  with check (public.has_project_permission('client_invoice.create', project_id));

drop policy if exists client_payments_select on public.client_payments;
create policy client_payments_select on public.client_payments
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('client_payment.read', project_id)
  );

drop policy if exists client_payments_write on public.client_payments;
create policy client_payments_write on public.client_payments
  for all to authenticated
  using (public.has_project_permission('client_payment.record', project_id))
  with check (public.has_project_permission('client_payment.record', project_id));

-- Variations
drop policy if exists variations_select on public.variations;
create policy variations_select on public.variations
  for select to authenticated
  using (
    public.can_access_project(project_id)
    and public.has_project_permission('variation.read', project_id)
  );

drop policy if exists variations_write on public.variations;
create policy variations_write on public.variations
  for all to authenticated
  using (
    public.has_project_permission('variation.create', project_id)
    or public.has_project_permission('variation.submit', project_id)
    or public.has_project_permission('variation.approve', project_id)
  )
  with check (
    public.has_project_permission('variation.create', project_id)
    or public.has_project_permission('variation.submit', project_id)
  );

drop policy if exists approval_threshold_rules_select on public.approval_threshold_rules;
create policy approval_threshold_rules_select on public.approval_threshold_rules
  for select to authenticated
  using (
    public.has_permission('finance.read', organization_id)
    or public.has_permission('procurement.read', organization_id)
    or public.has_permission('settings.manage', organization_id)
  );

drop policy if exists approval_threshold_rules_write on public.approval_threshold_rules;
create policy approval_threshold_rules_write on public.approval_threshold_rules
  for all to authenticated
  using (public.has_permission('settings.manage', organization_id)
    or public.has_permission('finance.manage', organization_id))
  with check (public.has_permission('settings.manage', organization_id)
    or public.has_permission('finance.manage', organization_id));

drop policy if exists commercial_number_counters_all on public.commercial_number_counters;
create policy commercial_number_counters_all on public.commercial_number_counters
  for all to authenticated
  using (public.has_project_permission('procurement.manage', project_id)
    or public.has_project_permission('purchase_request.create', project_id)
    or public.has_project_permission('finance.manage', project_id))
  with check (public.can_access_project(project_id));
