-- Master Touch OS — 046
-- Phase 3 live hardening:
-- 1) Issued PO immutability: RLS must not silently block before trigger (Phase 2 transmittal pattern)
-- 2) Expand locked PO statuses + protected commercial fields
-- 3) Finance org-scoped supplier_payment.record without project membership
-- 4) Stable overpayment error + invoice row lock (concurrency)
-- 5) Grant project_manager purchase_order.issue (live fixture + business flow)

-- =============================================================================
-- A. Locked PO helper
-- =============================================================================

create or replace function public.is_purchase_order_commercially_locked(
  p_status public.purchase_order_status,
  p_issued_at timestamptz
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_issued_at is not null
    or p_status in (
      'issued',
      'partially_delivered',
      'delivered',
      'partially_invoiced',
      'invoiced',
      'closed'
    );
$$;

-- =============================================================================
-- B. PO header immutability (trigger reaches authorized writers)
-- =============================================================================

create or replace function public.protect_issued_purchase_order()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return new;
  end if;

  if public.is_purchase_order_commercially_locked(old.status, old.issued_at) then
    if new.supplier_id is distinct from old.supplier_id
       or new.project_id is distinct from old.project_id
       or new.rfq_id is distinct from old.rfq_id
       or new.quotation_id is distinct from old.quotation_id
       or new.po_number is distinct from old.po_number
       or new.currency is distinct from old.currency
       or new.subtotal is distinct from old.subtotal
       or new.discount is distinct from old.discount
       or new.vat_rate_percent is distinct from old.vat_rate_percent
       or new.vat_amount is distinct from old.vat_amount
       or new.total is distinct from old.total
       or new.payment_terms is distinct from old.payment_terms
       or new.delivery_terms is distinct from old.delivery_terms
       or new.delivery_address is distinct from old.delivery_address
       or new.required_delivery_date is distinct from old.required_delivery_date
       or new.issue_date is distinct from old.issue_date
       or new.issued_at is distinct from old.issued_at then
      raise exception 'Issued purchase order is immutable'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists purchase_orders_protect_issued on public.purchase_orders;
create trigger purchase_orders_protect_issued
  before update on public.purchase_orders
  for each row execute function public.protect_issued_purchase_order();

-- =============================================================================
-- C. PO line immutability after parent issuance
-- =============================================================================

create or replace function public.protect_issued_purchase_order_items()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_status public.purchase_order_status;
  v_issued timestamptz;
  v_po_id uuid;
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_po_id := coalesce(new.purchase_order_id, old.purchase_order_id);

  select status, issued_at into v_status, v_issued
  from public.purchase_orders
  where id = v_po_id;

  if public.is_purchase_order_commercially_locked(v_status, v_issued) then
    if tg_op in ('INSERT', 'DELETE') then
      raise exception 'Issued purchase order items are immutable'
        using errcode = 'P0001';
    end if;

    if new.description is distinct from old.description
       or new.quantity is distinct from old.quantity
       or new.unit is distinct from old.unit
       or new.unit_price is distinct from old.unit_price
       or new.vat_amount is distinct from old.vat_amount
       or new.line_total is distinct from old.line_total
       or new.budget_item_id is distinct from old.budget_item_id
       or new.purchase_request_item_id is distinct from old.purchase_request_item_id
       or new.quotation_item_id is distinct from old.quotation_item_id
       or new.related_material_submittal_id is distinct from old.related_material_submittal_id
       or new.expected_delivery_date is distinct from old.expected_delivery_date
       or new.ordered_quantity is distinct from old.ordered_quantity then
      raise exception 'Issued purchase order items are immutable'
        using errcode = 'P0001';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists purchase_order_items_protect_issued on public.purchase_order_items;
create trigger purchase_order_items_protect_issued
  before insert or update or delete on public.purchase_order_items
  for each row execute function public.protect_issued_purchase_order_items();

-- =============================================================================
-- D. RLS — allow authorized UPDATE/DELETE to reach immutability triggers
-- ROOT CAUSE: purchase_order_items_all required purchase_order.create on WITH CHECK
-- while PM has approve (not create) → 0 rows, no error, trigger never fired.
-- =============================================================================

drop policy if exists purchase_orders_update on public.purchase_orders;
create policy purchase_orders_update on public.purchase_orders
  for update to authenticated
  using (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('purchase_order.create', project_id)
      or public.has_project_permission('purchase_order.approve', project_id)
      or public.has_project_permission('purchase_order.issue', project_id)
    )
  )
  with check (
    public.can_access_project(project_id)
    and (
      public.has_project_permission('purchase_order.create', project_id)
      or public.has_project_permission('purchase_order.approve', project_id)
      or public.has_project_permission('purchase_order.issue', project_id)
    )
  );

drop policy if exists purchase_order_items_all on public.purchase_order_items;
drop policy if exists purchase_order_items_select on public.purchase_order_items;
drop policy if exists purchase_order_items_insert on public.purchase_order_items;
drop policy if exists purchase_order_items_update on public.purchase_order_items;
drop policy if exists purchase_order_items_delete on public.purchase_order_items;

create policy purchase_order_items_select on public.purchase_order_items
  for select to authenticated
  using (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.can_access_project(po.project_id)
      and public.has_project_permission('purchase_order.read', po.project_id)
  ));

create policy purchase_order_items_insert on public.purchase_order_items
  for insert to authenticated
  with check (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.can_access_project(po.project_id)
      and (
        public.has_project_permission('purchase_order.create', po.project_id)
        or public.has_project_permission('purchase_order.approve', po.project_id)
        or public.has_project_permission('purchase_order.issue', po.project_id)
      )
  ));

create policy purchase_order_items_update on public.purchase_order_items
  for update to authenticated
  using (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.can_access_project(po.project_id)
      and (
        public.has_project_permission('purchase_order.create', po.project_id)
        or public.has_project_permission('purchase_order.approve', po.project_id)
        or public.has_project_permission('purchase_order.issue', po.project_id)
      )
  ))
  with check (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.can_access_project(po.project_id)
      and (
        public.has_project_permission('purchase_order.create', po.project_id)
        or public.has_project_permission('purchase_order.approve', po.project_id)
        or public.has_project_permission('purchase_order.issue', po.project_id)
      )
  ));

create policy purchase_order_items_delete on public.purchase_order_items
  for delete to authenticated
  using (exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and public.can_access_project(po.project_id)
      and (
        public.has_project_permission('purchase_order.create', po.project_id)
        or public.has_project_permission('purchase_order.approve', po.project_id)
        or public.has_project_permission('purchase_order.issue', po.project_id)
      )
  ));

-- =============================================================================
-- E. RBAC — PM must be able to issue PO (live fixture + operational flow)
-- ROOT CAUSE: issue_purchase_order failed FORBIDDEN → PO stayed approved →
-- immutability trigger never applied; UPDATE total succeeded silently.
-- =============================================================================

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'project_manager'
  and r.organization_id is null
  and p.key = 'purchase_order.issue'
on conflict do nothing;

-- =============================================================================
-- F. Supplier payment authorization + overpayment guard
-- ROOT CAUSE: has_project_permission requires can_access_project; finance_officer
-- is org-scoped without project membership → FORBIDDEN before validation.
-- =============================================================================

create or replace function public.can_record_supplier_payment(p_project_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_organization_member(p_organization_id)
    and (
      public.has_permission(
        'supplier_payment.record',
        p_organization_id,
        'organization',
        null
      )
      or (
        public.can_access_project(p_project_id)
        and public.has_permission(
          'supplier_payment.record',
          p_organization_id,
          'project',
          p_project_id
        )
      )
    );
$$;

grant execute on function public.can_record_supplier_payment(uuid, uuid) to authenticated;

create or replace function public.record_supplier_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_reference text,
  p_payment_method public.payment_method default 'bank_transfer',
  p_bank_reference text default null,
  p_notes text default null
)
returns public.supplier_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.supplier_invoices;
  v_paid numeric(18, 2);
  v_outstanding numeric(18, 2);
  v_pay public.supplier_payments;
begin
  select * into v_inv
  from public.supplier_invoices
  where id = p_invoice_id
  for update;

  if v_inv.id is null then
    raise exception 'NOT_FOUND';
  end if;

  if not public.can_record_supplier_payment(v_inv.project_id, v_inv.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'VALIDATION';
  end if;

  if p_payment_reference is null or length(trim(p_payment_reference)) = 0 then
    raise exception 'VALIDATION';
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.supplier_payments
  where supplier_invoice_id = v_inv.id;

  v_outstanding := v_inv.total - v_paid;

  if p_amount > v_outstanding + 0.001 then
    raise exception 'SUPPLIER_PAYMENT_EXCEEDS_INVOICE: payment exceeds invoice outstanding amount'
      using errcode = 'P0001';
  end if;

  insert into public.supplier_payments (
    organization_id, project_id, supplier_id, supplier_invoice_id,
    payment_reference, amount, payment_date, payment_method,
    bank_reference, notes, recorded_by
  ) values (
    v_inv.organization_id, v_inv.project_id, v_inv.supplier_id, v_inv.id,
    p_payment_reference, p_amount, p_payment_date, p_payment_method,
    p_bank_reference, p_notes, auth.uid()
  ) returning * into v_pay;

  v_paid := v_paid + p_amount;

  update public.supplier_invoices
  set status = case
        when v_paid >= v_inv.total - 0.001 then 'paid'::public.supplier_invoice_status
        else 'partially_paid'::public.supplier_invoice_status
      end
  where id = v_inv.id;

  perform public.log_audit(
    v_inv.organization_id, 'supplier_payment.recorded', 'supplier_payment', v_pay.id,
    null, to_jsonb(v_pay)
  );
  perform public.emit_domain_event(
    v_inv.organization_id, 'supplier_payment.recorded', 'supplier_payment', v_pay.id,
    jsonb_build_object('amount', p_amount, 'invoice_id', v_inv.id)
  );

  return v_pay;
end;
$$;

grant execute on function public.record_supplier_payment(uuid, numeric, date, text, public.payment_method, text, text) to authenticated;

comment on function public.protect_issued_purchase_order() is
  'Blocks commercial field changes when PO is issued or post-issue lifecycle status. Service-role may bypass for fixture cleanup.';

comment on function public.can_record_supplier_payment(uuid, uuid) is
  'Org-scoped supplier_payment.record for finance officers, or project-scoped with can_access_project.';

comment on function public.record_supplier_payment(uuid, numeric, date, text, public.payment_method, text, text) is
  'Records supplier payment with invoice row lock (FOR UPDATE) to prevent concurrent overpayment.';
