-- Master Touch OS — 048
-- Fix decide_entity_approval 22P02: composite approval_actions row was
-- assigned to the first uuid column of v_action.
--
-- Root cause (047 line 97):
--   select public.submit_approval_decision(...) into v_action;
-- PL/pgSQL treats SELECT fn() as a single-column result. v_action is
-- public.approval_actions whose first field is id uuid, so PostgreSQL
-- casts the whole record text to uuid → SQLSTATE 22P02.
--
-- submit_approval_decision RETURNS public.approval_actions (unchanged).
-- Consume it by composite assignment. Do not change that RPC contract.
--
-- Secondary: consume approve_variation (RETURNS public.variations) by
-- assignment. SELECT * FROM fn() was already valid; assignment matches
-- the composite-return pattern and avoids the SELECT fn() INTO trap.

create or replace function public.decide_entity_approval(
  p_request_id uuid,
  p_step_id uuid default null,
  p_official_code text default 'A',
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.approval_requests;
  v_step public.approval_steps;
  v_action public.approval_actions;
  v_next public.approval_steps;
  v_pr public.purchase_requests;
  v_cmp public.quotation_comparisons;
  v_po public.purchase_orders;
  v_invoice public.supplier_invoices;
  v_valuation public.client_valuations;
  v_variation public.variations;
  v_now timestamptz := timezone('utc', now());
  v_today date := (timezone('utc', now()))::date;
  v_supported boolean := false;
begin
  select * into v_request
  from public.approval_requests
  where id = p_request_id
  for update;

  if v_request.id is null then
    raise exception 'NOT_FOUND';
  end if;

  if v_request.entity_type in (
    'purchase_request',
    'quotation_comparison',
    'quotation_recommendation',
    'purchase_order',
    'supplier_invoice',
    'client_valuation',
    'variation'
  ) then
    v_supported := true;
  end if;

  if not v_supported then
    raise exception 'NOT_SUPPORTED';
  end if;

  if p_official_code = 'E' then
    raise exception 'VALIDATION';
  end if;

  if p_step_id is not null then
    select * into v_step
    from public.approval_steps
    where id = p_step_id
      and request_id = p_request_id
    for update;

    if v_step.id is null then
      raise exception 'NOT_FOUND';
    end if;
  else
    select * into v_step
    from public.approval_steps
    where request_id = p_request_id
      and status in ('pending', 'in_progress')
      and public.can_act_on_approval_step(id)
    order by
      case when status = 'in_progress' then 0 else 1 end,
      sequence
    limit 1
    for update;

    if v_step.id is null then
      raise exception 'FORBIDDEN';
    end if;

    if exists (
      select 1
      from public.approval_steps s
      where s.request_id = p_request_id
        and s.id <> v_step.id
        and s.status in ('pending', 'in_progress')
        and public.can_act_on_approval_step(s.id)
    ) then
      raise exception 'AMBIGUOUS_STEP';
    end if;
  end if;

  -- Composite RETURNS public.approval_actions must be assigned as a row.
  -- SELECT fn() INTO rowtype treats the composite as one column and
  -- casts it to the first field (id uuid) → 22P02.
  v_action := public.submit_approval_decision(v_step.id, p_official_code, p_comment);

  select * into v_request
  from public.approval_requests
  where id = p_request_id;

  select * into v_next
  from public.approval_steps
  where request_id = p_request_id
    and status in ('pending', 'in_progress')
  order by sequence
  limit 1;

  if v_request.status = 'completed' then
    if v_request.entity_type = 'purchase_request' then
      select * into v_pr from public.purchase_requests where id = v_request.entity_id for update;
      if v_pr.id is null then raise exception 'NOT_FOUND'; end if;

      if v_request.official_outcome in ('approved', 'approved_as_noted') then
        update public.purchase_requests
        set status = 'approved',
            approved_at = v_now,
            rejected_at = null
        where id = v_pr.id
        returning * into v_pr;

        perform public.log_audit(v_pr.organization_id, 'purchase_request.approved', 'purchase_request', v_pr.id, null, to_jsonb(v_pr));
        perform public.emit_domain_event(
          v_pr.organization_id,
          'purchase_request.approved',
          'purchase_request',
          v_pr.id,
          jsonb_build_object('pr_number', v_pr.pr_number)
        );
      elsif v_request.official_outcome = 'rejected' then
        update public.purchase_requests
        set status = 'rejected',
            approved_at = null,
            rejected_at = v_now
        where id = v_pr.id
        returning * into v_pr;

        perform public.log_audit(v_pr.organization_id, 'purchase_request.rejected', 'purchase_request', v_pr.id, null, to_jsonb(v_pr));
        perform public.emit_domain_event(
          v_pr.organization_id,
          'purchase_request.rejected',
          'purchase_request',
          v_pr.id,
          jsonb_build_object('pr_number', v_pr.pr_number)
        );
      elsif v_request.official_outcome = 'resubmit' then
        update public.purchase_requests
        set status = 'draft',
            approved_at = null,
            rejected_at = null
        where id = v_pr.id
        returning * into v_pr;

        perform public.log_audit(v_pr.organization_id, 'purchase_request.resubmitted', 'purchase_request', v_pr.id, null, to_jsonb(v_pr));
        perform public.emit_domain_event(
          v_pr.organization_id,
          'purchase_request.resubmitted',
          'purchase_request',
          v_pr.id,
          jsonb_build_object('pr_number', v_pr.pr_number)
        );
      end if;
    elsif v_request.entity_type in ('quotation_comparison', 'quotation_recommendation') then
      select * into v_cmp from public.quotation_comparisons where id = v_request.entity_id for update;
      if v_cmp.id is null then raise exception 'NOT_FOUND'; end if;

      if v_request.official_outcome in ('approved', 'approved_as_noted') then
        update public.quotation_comparisons
        set status = 'awarded'
        where id = v_cmp.id
        returning * into v_cmp;

        update public.rfqs
        set status = 'awarded'
        where id = v_cmp.rfq_id;

        if v_cmp.recommended_quotation_id is not null then
          update public.supplier_quotations
          set status = 'accepted'
          where id = v_cmp.recommended_quotation_id;
        end if;

        perform public.log_audit(v_cmp.organization_id, 'quotation.award_approved', 'quotation_comparison', v_cmp.id, null, to_jsonb(v_cmp));
        perform public.emit_domain_event(
          v_cmp.organization_id,
          'quotation.award_approved',
          'quotation_comparison',
          v_cmp.id,
          jsonb_build_object('rfq_id', v_cmp.rfq_id, 'quotation_id', v_cmp.recommended_quotation_id)
        );
      elsif v_request.official_outcome = 'rejected' then
        update public.quotation_comparisons
        set status = 'cancelled'
        where id = v_cmp.id
        returning * into v_cmp;

        update public.rfqs
        set status = 'under_comparison'
        where id = v_cmp.rfq_id;

        perform public.log_audit(v_cmp.organization_id, 'quotation.award_rejected', 'quotation_comparison', v_cmp.id, null, to_jsonb(v_cmp));
        perform public.emit_domain_event(
          v_cmp.organization_id,
          'quotation.award_rejected',
          'quotation_comparison',
          v_cmp.id,
          jsonb_build_object('rfq_id', v_cmp.rfq_id)
        );
      elsif v_request.official_outcome = 'resubmit' then
        update public.quotation_comparisons
        set status = 'recommended'
        where id = v_cmp.id
        returning * into v_cmp;

        update public.rfqs
        set status = 'under_comparison'
        where id = v_cmp.rfq_id;

        perform public.log_audit(v_cmp.organization_id, 'quotation.award_resubmitted', 'quotation_comparison', v_cmp.id, null, to_jsonb(v_cmp));
        perform public.emit_domain_event(
          v_cmp.organization_id,
          'quotation.award_resubmitted',
          'quotation_comparison',
          v_cmp.id,
          jsonb_build_object('rfq_id', v_cmp.rfq_id)
        );
      end if;
    elsif v_request.entity_type = 'purchase_order' then
      select * into v_po from public.purchase_orders where id = v_request.entity_id for update;
      if v_po.id is null then raise exception 'NOT_FOUND'; end if;

      if v_request.official_outcome in ('approved', 'approved_as_noted') then
        update public.purchase_orders
        set status = 'approved',
            approved_by = auth.uid()
        where id = v_po.id
        returning * into v_po;

        perform public.log_audit(v_po.organization_id, 'purchase_order.approved', 'purchase_order', v_po.id, null, to_jsonb(v_po));
        perform public.emit_domain_event(
          v_po.organization_id,
          'purchase_order.approved',
          'purchase_order',
          v_po.id,
          jsonb_build_object('po_number', v_po.po_number)
        );
      elsif v_request.official_outcome = 'rejected' then
        update public.purchase_orders
        set status = 'cancelled'
        where id = v_po.id
        returning * into v_po;

        perform public.log_audit(v_po.organization_id, 'purchase_order.rejected', 'purchase_order', v_po.id, null, to_jsonb(v_po));
        perform public.emit_domain_event(
          v_po.organization_id,
          'purchase_order.rejected',
          'purchase_order',
          v_po.id,
          jsonb_build_object('po_number', v_po.po_number)
        );
      elsif v_request.official_outcome = 'resubmit' then
        update public.purchase_orders
        set status = 'draft'
        where id = v_po.id
        returning * into v_po;

        perform public.log_audit(v_po.organization_id, 'purchase_order.resubmitted', 'purchase_order', v_po.id, null, to_jsonb(v_po));
        perform public.emit_domain_event(
          v_po.organization_id,
          'purchase_order.resubmitted',
          'purchase_order',
          v_po.id,
          jsonb_build_object('po_number', v_po.po_number)
        );
      end if;
    elsif v_request.entity_type = 'supplier_invoice' then
      select * into v_invoice from public.supplier_invoices where id = v_request.entity_id for update;
      if v_invoice.id is null then raise exception 'NOT_FOUND'; end if;

      if v_request.official_outcome in ('approved', 'approved_as_noted') then
        update public.supplier_invoices
        set status = 'approved_for_payment',
            reviewed_by = auth.uid()
        where id = v_invoice.id
        returning * into v_invoice;

        perform public.log_audit(v_invoice.organization_id, 'supplier_invoice.approved_for_payment', 'supplier_invoice', v_invoice.id, null, to_jsonb(v_invoice));
        perform public.emit_domain_event(
          v_invoice.organization_id,
          'supplier_invoice.approved_for_payment',
          'supplier_invoice',
          v_invoice.id,
          jsonb_build_object('invoice_number', v_invoice.invoice_number)
        );
      elsif v_request.official_outcome = 'rejected' then
        update public.supplier_invoices
        set status = 'rejected',
            reviewed_by = auth.uid()
        where id = v_invoice.id
        returning * into v_invoice;

        perform public.log_audit(v_invoice.organization_id, 'supplier_invoice.rejected', 'supplier_invoice', v_invoice.id, null, to_jsonb(v_invoice));
        perform public.emit_domain_event(
          v_invoice.organization_id,
          'supplier_invoice.rejected',
          'supplier_invoice',
          v_invoice.id,
          jsonb_build_object('invoice_number', v_invoice.invoice_number)
        );
      elsif v_request.official_outcome = 'resubmit' then
        update public.supplier_invoices
        set status = 'under_review',
            reviewed_by = auth.uid()
        where id = v_invoice.id
        returning * into v_invoice;

        perform public.log_audit(v_invoice.organization_id, 'supplier_invoice.resubmitted', 'supplier_invoice', v_invoice.id, null, to_jsonb(v_invoice));
        perform public.emit_domain_event(
          v_invoice.organization_id,
          'supplier_invoice.resubmitted',
          'supplier_invoice',
          v_invoice.id,
          jsonb_build_object('invoice_number', v_invoice.invoice_number)
        );
      end if;
    elsif v_request.entity_type = 'client_valuation' then
      select * into v_valuation from public.client_valuations where id = v_request.entity_id for update;
      if v_valuation.id is null then raise exception 'NOT_FOUND'; end if;

      if v_request.official_outcome in ('approved', 'approved_as_noted') then
        update public.client_valuations
        set status = 'certified',
            certification_date = v_today,
            certified_amount = coalesce(certified_amount, total_claim)
        where id = v_valuation.id
        returning * into v_valuation;

        perform public.log_audit(v_valuation.organization_id, 'client_valuation.certified', 'client_valuation', v_valuation.id, null, to_jsonb(v_valuation));
        perform public.emit_domain_event(
          v_valuation.organization_id,
          'client_valuation.certified',
          'client_valuation',
          v_valuation.id,
          jsonb_build_object('valuation_number', v_valuation.valuation_number)
        );
      elsif v_request.official_outcome = 'rejected' then
        update public.client_valuations
        set status = 'rejected'
        where id = v_valuation.id
        returning * into v_valuation;

        perform public.log_audit(v_valuation.organization_id, 'client_valuation.rejected', 'client_valuation', v_valuation.id, null, to_jsonb(v_valuation));
        perform public.emit_domain_event(
          v_valuation.organization_id,
          'client_valuation.rejected',
          'client_valuation',
          v_valuation.id,
          jsonb_build_object('valuation_number', v_valuation.valuation_number)
        );
      elsif v_request.official_outcome = 'resubmit' then
        update public.client_valuations
        set status = 'internal_review'
        where id = v_valuation.id
        returning * into v_valuation;

        perform public.log_audit(v_valuation.organization_id, 'client_valuation.resubmitted', 'client_valuation', v_valuation.id, null, to_jsonb(v_valuation));
        perform public.emit_domain_event(
          v_valuation.organization_id,
          'client_valuation.resubmitted',
          'client_valuation',
          v_valuation.id,
          jsonb_build_object('valuation_number', v_valuation.valuation_number)
        );
      end if;
    elsif v_request.entity_type = 'variation' then
      select * into v_variation from public.variations where id = v_request.entity_id for update;
      if v_variation.id is null then raise exception 'NOT_FOUND'; end if;

      if v_request.official_outcome in ('approved', 'approved_as_noted') then
        v_variation := public.approve_variation(
          v_variation.id,
          coalesce(v_variation.submitted_amount, v_variation.cost_impact, 0)
        );
      elsif v_request.official_outcome = 'rejected' then
        update public.variations
        set status = 'rejected'
        where id = v_variation.id
        returning * into v_variation;

        perform public.log_audit(v_variation.organization_id, 'variation.rejected', 'variation', v_variation.id, null, to_jsonb(v_variation));
        perform public.emit_domain_event(
          v_variation.organization_id,
          'variation.rejected',
          'variation',
          v_variation.id,
          jsonb_build_object('vo_number', v_variation.vo_number)
        );
      elsif v_request.official_outcome = 'resubmit' then
        update public.variations
        set status = 'under_review'
        where id = v_variation.id
        returning * into v_variation;

        perform public.log_audit(v_variation.organization_id, 'variation.resubmitted', 'variation', v_variation.id, null, to_jsonb(v_variation));
        perform public.emit_domain_event(
          v_variation.organization_id,
          'variation.resubmitted',
          'variation',
          v_variation.id,
          jsonb_build_object('vo_number', v_variation.vo_number)
        );
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'request_id', v_request.id,
    'step_id', v_step.id,
    'entity_type', v_request.entity_type,
    'entity_id', v_request.entity_id,
    'request_status', v_request.status,
    'official_outcome', v_request.official_outcome,
    'official_code', v_request.official_code,
    'next_step_id', v_next.id,
    'next_step_user_id', v_next.user_id
  );
end;
$$;

grant execute on function public.decide_entity_approval(uuid, uuid, text, text) to authenticated;
