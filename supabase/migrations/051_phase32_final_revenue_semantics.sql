-- Master Touch OS — 051
-- Phase 3.2 final revenue semantics:
-- 1) Invoice issue accepts partially_certified (and invoiced for cumulative invoices)
--    so the certified-amount cap is evaluated instead of false NOT_CERTIFIED.
-- 2) Payment after PAID reports CLIENT_PAYMENT_EXCEEDS_OUTSTANDING (outstanding=0)
--    rather than CLIENT_INVOICE_NOT_PAYABLE.
--
-- Do not modify 001–050. Apply via phase3_fix_051.sql only.

-- =============================================================================
-- A. issue_client_invoice — eligibility + certified remaining capacity
-- =============================================================================

create or replace function public.issue_client_invoice(p_invoice_id uuid)
returns public.client_invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.client_invoices;
  v_val public.client_valuations;
  v_certified numeric(18, 2);
  v_already_invoiced numeric(18, 2);
  v_available numeric(18, 2);
begin
  select * into v_inv from public.client_invoices where id = p_invoice_id for update;
  if v_inv.id is null then
    raise exception 'CLIENT_INVOICE_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  if not public.can_issue_client_invoice(v_inv.project_id, v_inv.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_inv.status <> 'draft' then
    raise exception 'CLIENT_INVOICE_NOT_ISSUABLE: only draft invoices can be issued'
      using errcode = 'P0001';
  end if;

  if v_inv.valuation_id is not null then
    select * into v_val from public.client_valuations where id = v_inv.valuation_id for update;
    if v_val.id is null then
      raise exception 'CLIENT_VALUATION_NOT_FOUND'
        using errcode = 'P0001';
    end if;

    -- Partial certification is a valid commercial state for invoicing.
    -- 'invoiced' / 'paid' remain eligible so cumulative invoices can use remaining certified capacity.
    if v_val.status not in ('certified', 'partially_certified', 'invoiced', 'paid') then
      raise exception 'CLIENT_VALUATION_NOT_CERTIFIED: valuation must be client-certified before invoice issue'
        using errcode = 'P0001';
    end if;

    if v_val.status = 'rejected' or coalesce(v_val.certified_amount, 0) <= 0 then
      raise exception 'CLIENT_VALUATION_NOT_CERTIFIED: valuation has no certified amount to invoice'
        using errcode = 'P0001';
    end if;

    v_certified := coalesce(v_val.certified_amount, 0);

    select coalesce(sum(ci.total), 0) into v_already_invoiced
    from public.client_invoices ci
    where ci.valuation_id = v_val.id
      and ci.id <> v_inv.id
      and ci.status in ('issued', 'partially_paid', 'paid', 'overdue');

    v_available := v_certified - v_already_invoiced;

    if v_inv.total > v_available + 0.001 then
      raise exception 'CLIENT_INVOICE_EXCEEDS_CERTIFIED_AMOUNT: invoice total exceeds remaining certified amount'
        using errcode = 'P0001';
    end if;
  end if;

  update public.client_invoices
  set status = 'issued',
      issued_at = timezone('utc', now())
  where id = p_invoice_id
  returning * into v_inv;

  if v_inv.valuation_id is not null then
    update public.client_valuations
    set status = 'invoiced'
    where id = v_inv.valuation_id
      and status in ('certified', 'partially_certified', 'invoiced');
  end if;

  perform public.log_audit(
    v_inv.organization_id, 'client_invoice.issued', 'client_invoice', v_inv.id, null, to_jsonb(v_inv)
  );
  perform public.emit_domain_event(
    v_inv.organization_id, 'client_invoice.issued', 'client_invoice', v_inv.id,
    jsonb_build_object('invoice_number', v_inv.invoice_number, 'total', v_inv.total)
  );

  return v_inv;
end;
$$;

grant execute on function public.issue_client_invoice(uuid) to authenticated;

comment on function public.issue_client_invoice(uuid) is
  'Issues draft client invoice. Accepts certified/partially_certified/invoiced valuations; caps cumulative total to certified_amount.';

-- =============================================================================
-- B. record_client_payment — outstanding check before operational status gate
-- =============================================================================

create or replace function public.record_client_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_received_date date,
  p_reference text,
  p_payment_method public.payment_method default 'bank_transfer'
)
returns public.client_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.client_invoices;
  v_paid numeric(18, 2);
  v_outstanding numeric(18, 2);
  v_pay public.client_payments;
begin
  -- 1. Lock invoice
  select * into v_inv from public.client_invoices where id = p_invoice_id for update;
  if v_inv.id is null then
    raise exception 'CLIENT_INVOICE_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  -- 2. Authorization
  if not public.can_record_client_payment(v_inv.project_id, v_inv.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  -- 3. Amount presence
  if p_amount is null or p_amount <= 0 then
    raise exception 'VALIDATION';
  end if;

  if p_reference is null or length(trim(p_reference)) = 0 then
    raise exception 'VALIDATION';
  end if;

  if exists (
    select 1 from public.client_payments
    where organization_id = v_inv.organization_id
      and reference = p_reference
  ) then
    raise exception 'CLIENT_PAYMENT_DUPLICATE_REFERENCE: payment reference already used'
      using errcode = 'P0001';
  end if;

  -- 4. Outstanding (authoritative under row lock)
  select coalesce(sum(amount), 0) into v_paid
  from public.client_payments
  where client_invoice_id = v_inv.id;

  v_outstanding := v_inv.total - v_paid;

  -- 5. Over-collection / zero outstanding (includes status=paid with outstanding=0)
  if p_amount > v_outstanding + 0.001 then
    raise exception 'CLIENT_PAYMENT_EXCEEDS_OUTSTANDING: payment exceeds invoice outstanding amount'
      using errcode = 'P0001';
  end if;

  -- 6. Operational state for draft/cancelled/etc. (paid already blocked above when outstanding=0)
  if v_inv.status not in ('issued', 'partially_paid', 'overdue') then
    raise exception 'CLIENT_INVOICE_NOT_PAYABLE: invoice is not in a payable operational state'
      using errcode = 'P0001';
  end if;

  insert into public.client_payments (
    organization_id, project_id, client_invoice_id,
    amount, received_date, reference, payment_method, recorded_by
  ) values (
    v_inv.organization_id, v_inv.project_id, v_inv.id,
    p_amount, p_received_date, p_reference, p_payment_method, auth.uid()
  ) returning * into v_pay;

  v_paid := v_paid + p_amount;

  update public.client_invoices
  set status = case
        when v_paid >= v_inv.total - 0.001 then 'paid'::public.client_invoice_status
        else 'partially_paid'::public.client_invoice_status
      end
  where id = v_inv.id;

  if v_inv.valuation_id is not null and v_paid >= v_inv.total - 0.001 then
    update public.client_valuations
    set status = 'paid'
    where id = v_inv.valuation_id
      and status in ('invoiced', 'certified', 'partially_certified');
  end if;

  perform public.log_audit(
    v_inv.organization_id, 'client_payment.received', 'client_payment', v_pay.id, null, to_jsonb(v_pay)
  );
  perform public.emit_domain_event(
    v_inv.organization_id, 'client_payment.received', 'client_payment', v_pay.id,
    jsonb_build_object('amount', p_amount, 'invoice_id', v_inv.id)
  );

  return v_pay;
end;
$$;

grant execute on function public.record_client_payment(uuid, numeric, date, text, public.payment_method) to authenticated;

comment on function public.record_client_payment(uuid, numeric, date, text, public.payment_method) is
  'Records client receipt with FOR UPDATE lock. Over-collection (incl. paid/outstanding=0) → CLIENT_PAYMENT_EXCEEDS_OUTSTANDING.';
