-- Master Touch OS — 044
-- Phase 3 RPCs: numbering, supplier create, payments, match, commercial summary/health.

create or replace function public.generate_supplier_code(p_organization_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_value integer;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  insert into public.supplier_counters (organization_id, next_value)
  values (p_organization_id, 1)
  on conflict (organization_id) do update
    set next_value = public.supplier_counters.next_value + 1
  returning next_value into v_value;

  return 'SUP-' || lpad(v_value::text, 4, '0');
end;
$$;

grant execute on function public.generate_supplier_code(uuid) to authenticated;

create or replace function public.generate_commercial_number(
  p_organization_id uuid,
  p_project_id uuid,
  p_doc_type text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_code text;
  v_value integer;
  v_abbr text;
begin
  if not public.can_access_project(p_project_id) then
    raise exception 'FORBIDDEN';
  end if;

  select project_code into v_project_code
  from public.projects
  where id = p_project_id and organization_id = p_organization_id;
  if v_project_code is null then
    raise exception 'NOT_FOUND';
  end if;

  v_abbr := upper(p_doc_type);

  insert into public.commercial_number_counters (
    organization_id, project_id, doc_type, next_value
  ) values (
    p_organization_id, p_project_id, v_abbr, 1
  )
  on conflict (organization_id, project_id, doc_type) do update
    set next_value = public.commercial_number_counters.next_value + 1
  returning next_value into v_value;

  return format('MT-%s-%s-%s', v_project_code, v_abbr, lpad(v_value::text, 4, '0'));
end;
$$;

grant execute on function public.generate_commercial_number(uuid, uuid, text) to authenticated;

-- Supplier bank details: privileged read only
create or replace function public.get_supplier_banking(p_supplier_id uuid)
returns table (bank_name text, iban text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from public.suppliers where id = p_supplier_id;
  if v_org is null then
    raise exception 'NOT_FOUND';
  end if;
  if not (
    public.has_permission('supplier.manage', v_org)
    or public.has_permission('finance.manage', v_org)
    or public.has_permission('finance.read', v_org)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  return query
  select s.bank_name, s.iban
  from public.suppliers s
  where s.id = p_supplier_id;
end;
$$;

grant execute on function public.get_supplier_banking(uuid) to authenticated;

-- Record supplier payment with overpayment guard
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
  v_pay public.supplier_payments;
begin
  select * into v_inv from public.supplier_invoices where id = p_invoice_id for update;
  if v_inv.id is null then raise exception 'NOT_FOUND'; end if;

  if not public.has_project_permission('supplier_payment.record', v_inv.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'VALIDATION';
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.supplier_payments
  where supplier_invoice_id = v_inv.id;

  if v_paid + p_amount > v_inv.total + 0.001 then
    raise exception 'VALIDATION: payment exceeds invoice total'
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
        when v_paid >= v_inv.total then 'paid'::public.supplier_invoice_status
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

-- Three-way match flags for supplier invoice
create or replace function public.evaluate_supplier_invoice_match(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.supplier_invoices;
  v_po_total numeric(18, 2);
  v_received numeric(18, 4);
  v_ordered numeric(18, 4);
  v_flags jsonb := '[]'::jsonb;
begin
  select * into v_inv from public.supplier_invoices where id = p_invoice_id;
  if v_inv.id is null then raise exception 'NOT_FOUND'; end if;

  if v_inv.purchase_order_id is not null then
    select total into v_po_total from public.purchase_orders where id = v_inv.purchase_order_id;
    if v_inv.total > coalesce(v_po_total, 0) + 0.01 then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'invoice_gt_po', 'severity', 'high'));
    end if;

    select coalesce(sum(quantity), 0), coalesce(sum(received_quantity), 0)
      into v_ordered, v_received
    from public.purchase_order_items
    where purchase_order_id = v_inv.purchase_order_id;

    if v_inv.total > 0 and v_received < v_ordered and v_received = 0 then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'invoice_without_receipt', 'severity', 'medium'));
    end if;
  else
    v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'missing_po', 'severity', 'medium'));
  end if;

  update public.supplier_invoices
  set match_flags = v_flags,
      status = case
        when jsonb_array_length(v_flags) > 0 then 'discrepancy'::public.supplier_invoice_status
        when status = 'received' then 'matched'::public.supplier_invoice_status
        else status
      end
  where id = p_invoice_id;

  if jsonb_array_length(v_flags) > 0 then
    perform public.emit_domain_event(
      v_inv.organization_id, 'supplier_invoice.discrepancy', 'supplier_invoice', p_invoice_id,
      jsonb_build_object('flags', v_flags)
    );
  end if;

  return v_flags;
end;
$$;

grant execute on function public.evaluate_supplier_invoice_match(uuid) to authenticated;

-- Issue PO
create or replace function public.issue_purchase_order(p_po_id uuid)
returns public.purchase_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po public.purchase_orders;
  v_count integer;
begin
  select * into v_po from public.purchase_orders where id = p_po_id for update;
  if v_po.id is null then raise exception 'NOT_FOUND'; end if;
  if v_po.status not in ('approved', 'draft') then raise exception 'CONFLICT'; end if;
  if not public.has_project_permission('purchase_order.issue', v_po.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  select count(*) into v_count from public.purchase_order_items where purchase_order_id = v_po.id;
  if v_count = 0 then raise exception 'VALIDATION'; end if;

  update public.purchase_order_items
  set ordered_quantity = quantity
  where purchase_order_id = v_po.id;

  update public.purchase_orders
  set status = 'issued',
      issue_date = (timezone('utc', now()))::date,
      issued_at = timezone('utc', now())
  where id = v_po.id
  returning * into v_po;

  perform public.log_audit(
    v_po.organization_id, 'purchase_order.issued', 'purchase_order', v_po.id, null, to_jsonb(v_po)
  );
  perform public.emit_domain_event(
    v_po.organization_id, 'purchase_order.issued', 'purchase_order', v_po.id,
    jsonb_build_object('po_number', v_po.po_number, 'total', v_po.total)
  );

  return v_po;
end;
$$;

grant execute on function public.issue_purchase_order(uuid) to authenticated;

-- Apply goods receipt quantities to PO lines (over-receipt blocked)
create or replace function public.post_goods_receipt(p_receipt_id uuid)
returns public.goods_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gr public.goods_receipts;
  r record;
  v_new_received numeric(18, 4);
begin
  select * into v_gr from public.goods_receipts where id = p_receipt_id for update;
  if v_gr.id is null then raise exception 'NOT_FOUND'; end if;
  if not public.has_project_permission('goods_receipt.manage', v_gr.project_id)
     and not public.has_project_permission('goods_receipt.create', v_gr.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  for r in
    select * from public.goods_receipt_items where goods_receipt_id = p_receipt_id
  loop
    select received_quantity + r.accepted_quantity into v_new_received
    from public.purchase_order_items
    where id = r.purchase_order_item_id
    for update;

    if v_new_received > (
      select quantity from public.purchase_order_items where id = r.purchase_order_item_id
    ) + 0.0001 then
      raise exception 'VALIDATION: received quantity exceeds ordered'
        using errcode = 'P0001';
    end if;

    update public.purchase_order_items
    set received_quantity = received_quantity + r.accepted_quantity
    where id = r.purchase_order_item_id;
  end loop;

  update public.goods_receipts
  set status = 'accepted'
  where id = p_receipt_id
  returning * into v_gr;

  -- Update PO delivery status
  update public.purchase_orders po
  set status = case
    when exists (
      select 1 from public.purchase_order_items i
      where i.purchase_order_id = po.id and i.received_quantity < i.quantity
    ) then 'partially_delivered'::public.purchase_order_status
    else 'delivered'::public.purchase_order_status
  end
  where po.id = v_gr.purchase_order_id
    and po.status in ('issued', 'partially_delivered');

  perform public.emit_domain_event(
    v_gr.organization_id, 'goods_receipt.received', 'goods_receipt', v_gr.id,
    jsonb_build_object('receipt_number', v_gr.receipt_number)
  );

  return v_gr;
end;
$$;

grant execute on function public.post_goods_receipt(uuid) to authenticated;

-- Approve variation: preserve original contract; accumulate approved VO amount into budget notes via event
create or replace function public.approve_variation(
  p_variation_id uuid,
  p_approved_amount numeric
)
returns public.variations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vo public.variations;
begin
  select * into v_vo from public.variations where id = p_variation_id for update;
  if v_vo.id is null then raise exception 'NOT_FOUND'; end if;
  if not public.has_project_permission('variation.approve', v_vo.project_id) then
    raise exception 'FORBIDDEN';
  end if;
  if p_approved_amount is null then raise exception 'VALIDATION'; end if;

  update public.variations
  set status = 'approved',
      approved_amount = p_approved_amount,
      approval_date = (timezone('utc', now()))::date
  where id = p_variation_id
  returning * into v_vo;

  -- Bump project budget approved variation total if budget exists
  update public.project_budgets
  set approved_variation_amount = approved_variation_amount + p_approved_amount,
      status = 'revised'
  where project_id = v_vo.project_id;

  perform public.log_audit(
    v_vo.organization_id, 'variation.approved', 'variation', v_vo.id, null, to_jsonb(v_vo)
  );
  perform public.emit_domain_event(
    v_vo.organization_id, 'variation.approved', 'variation', v_vo.id,
    jsonb_build_object('approved_amount', p_approved_amount, 'vo_number', v_vo.vo_number)
  );

  return v_vo;
end;
$$;

grant execute on function public.approve_variation(uuid, numeric) to authenticated;

-- Project commercial summary (derived)
create or replace function public.compute_project_commercial_summary(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_original_contract numeric(18, 2) := 0;
  v_approved_vo numeric(18, 2) := 0;
  v_original_budget numeric(18, 2) := 0;
  v_budget_vo numeric(18, 2) := 0;
  v_committed numeric(18, 2) := 0;
  v_ap numeric(18, 2) := 0;
  v_ar numeric(18, 2) := 0;
  v_invoiced_rev numeric(18, 2) := 0;
  v_collected numeric(18, 2) := 0;
  v_revised_contract numeric(18, 2);
  v_revised_budget numeric(18, 2);
  v_margin numeric(18, 2);
begin
  select organization_id into v_org from public.projects where id = p_project_id;
  if v_org is null then raise exception 'NOT_FOUND'; end if;

  if not public.can_access_project(p_project_id) then
    raise exception 'FORBIDDEN';
  end if;
  if not (
    public.has_project_permission('finance.read', p_project_id)
    or public.has_project_permission('commercial_reports.read', p_project_id)
    or public.has_project_permission('project_budget.read', p_project_id)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  select coalesce(sum(contract_value), 0) into v_original_contract
  from public.project_contracts
  where project_id = p_project_id and status in ('active', 'completed', 'draft');

  select coalesce(sum(coalesce(approved_amount, 0)), 0) into v_approved_vo
  from public.variations
  where project_id = p_project_id and status in ('approved', 'partially_approved');

  select coalesce(original_budget_amount, 0), coalesce(approved_variation_amount, 0)
    into v_original_budget, v_budget_vo
  from public.project_budgets
  where project_id = p_project_id;

  select coalesce(sum(total), 0) into v_committed
  from public.purchase_orders
  where project_id = p_project_id
    and status in ('approved', 'issued', 'partially_delivered', 'delivered', 'partially_invoiced', 'invoiced', 'closed');

  select coalesce(sum(si.total), 0) - coalesce((
    select sum(sp.amount) from public.supplier_payments sp where sp.project_id = p_project_id
  ), 0)
  into v_ap
  from public.supplier_invoices si
  where si.project_id = p_project_id
    and si.status not in ('cancelled', 'rejected');

  select coalesce(sum(total), 0) into v_invoiced_rev
  from public.client_invoices
  where project_id = p_project_id and status in ('issued', 'partially_paid', 'paid', 'overdue');

  select coalesce(sum(amount), 0) into v_collected
  from public.client_payments
  where project_id = p_project_id;

  v_ar := v_invoiced_rev - v_collected;
  v_revised_contract := v_original_contract + v_approved_vo;
  v_revised_budget := v_original_budget + v_budget_vo;
  v_margin := v_revised_contract - greatest(v_committed, v_revised_budget * 0); -- forecast uses committed as proxy

  return jsonb_build_object(
    'original_contract_value', v_original_contract,
    'approved_variations', v_approved_vo,
    'revised_contract_value', v_revised_contract,
    'original_budget', v_original_budget,
    'revised_budget', v_revised_budget,
    'committed_cost', v_committed,
    'accounts_payable', v_ap,
    'invoiced_revenue', v_invoiced_rev,
    'collected_revenue', v_collected,
    'accounts_receivable', v_ar,
    'gross_margin_estimate', v_revised_contract - v_committed
  );
end;
$$;

grant execute on function public.compute_project_commercial_summary(uuid) to authenticated;

create or replace function public.compute_project_commercial_health(p_project_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_summary jsonb;
  v_committed numeric;
  v_revised_budget numeric;
  v_margin numeric;
  v_overdue_ap integer;
  v_overdue_ar integer;
  v_unapproved_vo integer;
begin
  if not public.can_access_project(p_project_id) then
    raise exception 'FORBIDDEN';
  end if;

  v_summary := public.compute_project_commercial_summary(p_project_id);
  v_committed := (v_summary ->> 'committed_cost')::numeric;
  v_revised_budget := (v_summary ->> 'revised_budget')::numeric;
  v_margin := (v_summary ->> 'gross_margin_estimate')::numeric;

  select count(*) into v_overdue_ap
  from public.supplier_invoices
  where project_id = p_project_id
    and due_date < (timezone('utc', now()))::date
    and status in ('received', 'under_review', 'matched', 'discrepancy', 'approved_for_payment', 'partially_paid');

  select count(*) into v_overdue_ar
  from public.client_invoices
  where project_id = p_project_id
    and due_date < (timezone('utc', now()))::date
    and status in ('issued', 'partially_paid', 'overdue');

  select count(*) into v_unapproved_vo
  from public.variations
  where project_id = p_project_id
    and status in ('submitted', 'negotiation', 'under_review')
    and submitted_date is not null
    and submitted_date < (timezone('utc', now()))::date - 14;

  -- RED rules
  if v_revised_budget > 0 and v_committed > v_revised_budget then
    return 'red';
  end if;
  if v_margin < 0 then
    return 'red';
  end if;
  if v_overdue_ar >= 3 or v_overdue_ap >= 5 then
    return 'red';
  end if;

  -- AMBER
  if v_revised_budget > 0 and v_committed > v_revised_budget * 0.9 then
    return 'amber';
  end if;
  if v_overdue_ap > 0 or v_overdue_ar > 0 or v_unapproved_vo > 0 then
    return 'amber';
  end if;

  return 'green';
end;
$$;

grant execute on function public.compute_project_commercial_health(uuid) to authenticated;

comment on function public.compute_project_commercial_health(uuid) is
  'Deterministic commercial health: RED if committed>budget or negative margin or severe overdue AR/AP; AMBER if near budget / overdue / VO pending >14d; else GREEN.';
