-- Master Touch OS — phase3_fix_049
-- Apply this file in the Supabase Dashboard SQL Editor (or via scripts/apply-phase3-migration-049.ts).
-- Equivalent to migrations/049_phase32_client_revenue_hardening.sql
--
-- Root causes addressed:
-- 1) Client payment over-collection possible without FOR UPDATE row lock (app-only check)
-- 2) Issued client invoices lacked DB immutability (unlike PO in 046)
-- 3) decide_entity_approval conflated internal valuation approval with client certification
-- 4) approve_variation ignored partially_approved status
-- 5) Single attachment_document_id insufficient for multi-file commercial entities
-- 6) finance_manager missing client_valuation.create/submit/approve permissions

-- Master Touch OS — 049
-- Phase 3.2 client revenue hardening:
-- 1) entity_documents junction for multi-attachment commercial entities
-- 2) Client payment RPC with row lock + org-scoped auth (mirror 046 supplier)
-- 3) Issued client invoice immutability (mirror PO)
-- 4) Separate internal approval vs external client certification for valuations
-- 5) Partial variation approval
-- 6) Milestone eligibility audit + valuation certification fields
-- 7) issue_client_invoice + activate_contract + mark_milestone_eligible RPCs

-- =============================================================================
-- A. entity_documents junction
-- =============================================================================

create table if not exists public.entity_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid references public.projects (id) on delete set null,
  entity_type text not null,
  entity_id uuid not null,
  document_id uuid not null references public.documents (id) on delete cascade,
  role text not null default 'attachment',
  uploaded_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  unique (entity_type, entity_id, document_id)
);

create index if not exists entity_documents_entity_idx
  on public.entity_documents (entity_type, entity_id);
create index if not exists entity_documents_org_idx
  on public.entity_documents (organization_id, entity_type);

alter table public.entity_documents enable row level security;

create policy entity_documents_select on public.entity_documents
  for select to authenticated
  using (
    public.is_organization_member(organization_id)
    and (
      project_id is null
      or public.can_access_project(project_id)
    )
  );

create policy entity_documents_insert on public.entity_documents
  for insert to authenticated
  with check (
    public.is_organization_member(organization_id)
    and uploaded_by = auth.uid()
    and (
      project_id is null
      or public.can_access_project(project_id)
    )
  );

create policy entity_documents_delete on public.entity_documents
  for delete to authenticated
  using (
    public.is_organization_member(organization_id)
    and uploaded_by = auth.uid()
  );

-- =============================================================================
-- B. Schema extensions
-- =============================================================================

alter table public.variations
  add column if not exists requested_amount numeric(18, 2) not null default 0;

update public.variations
set requested_amount = coalesce(nullif(submitted_amount, 0), cost_impact, 0)
where requested_amount = 0;

alter table public.client_valuations
  add column if not exists milestone_id uuid references public.contract_milestones (id) on delete set null,
  add column if not exists client_reference text,
  add column if not exists rejected_amount numeric(18, 2),
  add column if not exists certification_comments text,
  add column if not exists response_received_by uuid references public.profiles (id) on delete set null,
  add column if not exists notes text;

alter table public.contract_milestones
  add column if not exists name text,
  add column if not exists eligible_by uuid references public.profiles (id) on delete set null,
  add column if not exists eligible_at timestamptz,
  add column if not exists eligibility_comments text;

update public.contract_milestones
set name = coalesce(name, description)
where name is null;

create unique index if not exists client_payments_reference_org_unique_idx
  on public.client_payments (organization_id, reference)
  where reference is not null and length(trim(reference)) > 0;

-- =============================================================================
-- C. Valuation totals (authoritative server-side)
-- =============================================================================

create or replace function public.recalculate_client_valuation(p_valuation_id uuid)
returns public.client_valuations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_val public.client_valuations;
  v_contract public.project_contracts;
  v_retention_pct numeric(6, 3);
  v_vat_rate numeric(6, 3) := 15;
  v_gross numeric(18, 2);
  v_retention numeric(18, 2);
  v_net_before_vat numeric(18, 2);
begin
  select * into v_val from public.client_valuations where id = p_valuation_id for update;
  if v_val.id is null then raise exception 'NOT_FOUND'; end if;

  if not public.has_project_permission('client_valuation.create', v_val.project_id)
     and not public.has_project_permission('client_valuation.submit', v_val.project_id)
     and not public.has_project_permission('finance.manage', v_val.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_contract from public.project_contracts where id = v_val.contract_id;
  v_retention_pct := coalesce(v_contract.retention_percent, 0);
  if v_contract.vat_amount > 0 and v_contract.contract_value > 0 then
    v_vat_rate := round((v_contract.vat_amount / v_contract.contract_value) * 100, 3);
  end if;

  v_gross := coalesce(v_val.gross_work_value, 0) + coalesce(v_val.variations_amount, 0);
  v_retention := round(v_gross * (v_retention_pct / 100), 2);
  v_net_before_vat := v_gross - v_retention - coalesce(v_val.advance_recovery, 0) - coalesce(v_val.previous_certified_amount, 0);

  update public.client_valuations
  set retention_amount = v_retention,
      current_claim_amount = greatest(v_net_before_vat, 0),
      vat_amount = round(greatest(v_net_before_vat, 0) * (v_vat_rate / 100), 2),
      total_claim = round(greatest(v_net_before_vat, 0) * (1 + v_vat_rate / 100), 2)
  where id = p_valuation_id
  returning * into v_val;

  return v_val;
end;
$$;

grant execute on function public.recalculate_client_valuation(uuid) to authenticated;

-- =============================================================================
-- D. Contract activation
-- =============================================================================

create or replace function public.activate_project_contract(p_contract_id uuid)
returns public.project_contracts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contract public.project_contracts;
begin
  select * into v_contract from public.project_contracts where id = p_contract_id for update;
  if v_contract.id is null then raise exception 'NOT_FOUND'; end if;

  if not public.has_project_permission('finance.manage', v_contract.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'CONFLICT';
  end if;

  update public.project_contracts
  set status = 'active'
  where id = p_contract_id
  returning * into v_contract;

  perform public.log_audit(
    v_contract.organization_id, 'contract.activated', 'project_contract', v_contract.id, null, to_jsonb(v_contract)
  );
  perform public.emit_domain_event(
    v_contract.organization_id, 'contract.activated', 'project_contract', v_contract.id,
    jsonb_build_object('contract_number', v_contract.contract_number, 'contract_value', v_contract.contract_value)
  );

  return v_contract;
end;
$$;

grant execute on function public.activate_project_contract(uuid) to authenticated;

-- =============================================================================
-- E. Milestone eligibility
-- =============================================================================

create or replace function public.mark_contract_milestone_eligible(
  p_milestone_id uuid,
  p_comments text default null
)
returns public.contract_milestones
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ms public.contract_milestones;
begin
  select * into v_ms from public.contract_milestones where id = p_milestone_id for update;
  if v_ms.id is null then raise exception 'NOT_FOUND'; end if;

  if not public.has_project_permission('finance.manage', v_ms.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_ms.status not in ('planned') then
    raise exception 'CONFLICT';
  end if;

  update public.contract_milestones
  set status = 'eligible',
      actual_eligible_date = (timezone('utc', now()))::date,
      eligible_by = auth.uid(),
      eligible_at = timezone('utc', now()),
      eligibility_comments = p_comments
  where id = p_milestone_id
  returning * into v_ms;

  perform public.log_audit(
    v_ms.organization_id, 'milestone.eligible', 'contract_milestone', v_ms.id, null, to_jsonb(v_ms)
  );
  perform public.emit_domain_event(
    v_ms.organization_id, 'milestone.eligible', 'contract_milestone', v_ms.id,
    jsonb_build_object('milestone_number', v_ms.milestone_number)
  );

  return v_ms;
end;
$$;

grant execute on function public.mark_contract_milestone_eligible(uuid, text) to authenticated;

-- =============================================================================
-- F. Fix decide_entity_approval — internal valuation approval ≠ client certification
-- =============================================================================

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
        update public.supplier_invoices set status = 'approved_for_payment', reviewed_by = auth.uid() where id = v_invoice.id returning * into v_invoice;
        perform public.log_audit(v_invoice.organization_id, 'supplier_invoice.approved_for_payment', 'supplier_invoice', v_invoice.id, null, to_jsonb(v_invoice));
        perform public.emit_domain_event(v_invoice.organization_id, 'supplier_invoice.approved_for_payment', 'supplier_invoice', v_invoice.id, jsonb_build_object('invoice_number', v_invoice.invoice_number));
      elsif v_request.official_outcome = 'rejected' then
        update public.supplier_invoices set status = 'rejected', reviewed_by = auth.uid() where id = v_invoice.id returning * into v_invoice;
        perform public.log_audit(v_invoice.organization_id, 'supplier_invoice.rejected', 'supplier_invoice', v_invoice.id, null, to_jsonb(v_invoice));
        perform public.emit_domain_event(v_invoice.organization_id, 'supplier_invoice.rejected', 'supplier_invoice', v_invoice.id, jsonb_build_object('invoice_number', v_invoice.invoice_number));
      elsif v_request.official_outcome = 'resubmit' then
        update public.supplier_invoices set status = 'under_review', reviewed_by = auth.uid() where id = v_invoice.id returning * into v_invoice;
        perform public.log_audit(v_invoice.organization_id, 'supplier_invoice.resubmitted', 'supplier_invoice', v_invoice.id, null, to_jsonb(v_invoice));
        perform public.emit_domain_event(v_invoice.organization_id, 'supplier_invoice.resubmitted', 'supplier_invoice', v_invoice.id, jsonb_build_object('invoice_number', v_invoice.invoice_number));
      end if;
    elsif v_request.entity_type = 'client_valuation' then
      select * into v_valuation from public.client_valuations where id = v_request.entity_id for update;
      if v_valuation.id is null then raise exception 'NOT_FOUND'; end if;

      -- Internal approval only — does NOT certify with client
      if v_request.official_outcome in ('approved', 'approved_as_noted') then
        update public.client_valuations
        set status = 'submitted',
            submitted_date = coalesce(submitted_date, v_today)
        where id = v_valuation.id
        returning * into v_valuation;

        perform public.log_audit(v_valuation.organization_id, 'client_valuation.internal_approved', 'client_valuation', v_valuation.id, null, to_jsonb(v_valuation));
        perform public.emit_domain_event(
          v_valuation.organization_id, 'client_valuation.submitted', 'client_valuation', v_valuation.id,
          jsonb_build_object('valuation_number', v_valuation.valuation_number, 'total_claim', v_valuation.total_claim)
        );
      elsif v_request.official_outcome = 'rejected' then
        update public.client_valuations set status = 'rejected' where id = v_valuation.id returning * into v_valuation;
        perform public.log_audit(v_valuation.organization_id, 'client_valuation.rejected', 'client_valuation', v_valuation.id, null, to_jsonb(v_valuation));
        perform public.emit_domain_event(v_valuation.organization_id, 'client_valuation.rejected', 'client_valuation', v_valuation.id, jsonb_build_object('valuation_number', v_valuation.valuation_number));
      elsif v_request.official_outcome = 'resubmit' then
        update public.client_valuations set status = 'internal_review' where id = v_valuation.id returning * into v_valuation;
        perform public.log_audit(v_valuation.organization_id, 'client_valuation.resubmitted', 'client_valuation', v_valuation.id, null, to_jsonb(v_valuation));
        perform public.emit_domain_event(v_valuation.organization_id, 'client_valuation.resubmitted', 'client_valuation', v_valuation.id, jsonb_build_object('valuation_number', v_valuation.valuation_number));
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
        update public.variations set status = 'rejected' where id = v_variation.id returning * into v_variation;
        perform public.log_audit(v_variation.organization_id, 'variation.rejected', 'variation', v_variation.id, null, to_jsonb(v_variation));
        perform public.emit_domain_event(v_variation.organization_id, 'variation.rejected', 'variation', v_variation.id, jsonb_build_object('vo_number', v_variation.vo_number));
      elsif v_request.official_outcome = 'resubmit' then
        update public.variations set status = 'under_review' where id = v_variation.id returning * into v_variation;
        perform public.log_audit(v_variation.organization_id, 'variation.resubmitted', 'variation', v_variation.id, null, to_jsonb(v_variation));
        perform public.emit_domain_event(v_variation.organization_id, 'variation.resubmitted', 'variation', v_variation.id, jsonb_build_object('vo_number', v_variation.vo_number));
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

-- =============================================================================
-- G. External client certification (separate from internal approval)
-- =============================================================================

create or replace function public.record_client_valuation_certification(
  p_valuation_id uuid,
  p_client_reference text,
  p_certified_amount numeric,
  p_certification_date date default null,
  p_comments text default null
)
returns public.client_valuations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_val public.client_valuations;
  v_rejected numeric(18, 2);
  v_cert_date date := coalesce(p_certification_date, (timezone('utc', now()))::date);
begin
  select * into v_val from public.client_valuations where id = p_valuation_id for update;
  if v_val.id is null then raise exception 'NOT_FOUND'; end if;

  if not (
    public.has_project_permission('client_valuation.approve', v_val.project_id)
    or public.has_project_permission('finance.manage', v_val.project_id)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if v_val.status not in ('submitted', 'under_client_review') then
    raise exception 'CONFLICT';
  end if;

  if p_certified_amount is null or p_certified_amount < 0 then
    raise exception 'VALIDATION';
  end if;

  if p_certified_amount > v_val.total_claim + 0.001 then
    raise exception 'VALIDATION: certified amount exceeds submitted claim'
      using errcode = 'P0001';
  end if;

  v_rejected := round(v_val.total_claim - p_certified_amount, 2);

  update public.client_valuations
  set status = case
        when p_certified_amount <= 0.001 then 'rejected'::public.valuation_status
        when p_certified_amount < v_val.total_claim - 0.001 then 'partially_certified'::public.valuation_status
        else 'certified'::public.valuation_status
      end,
      client_reference = p_client_reference,
      certified_amount = p_certified_amount,
      rejected_amount = v_rejected,
      certification_date = v_cert_date,
      certification_comments = p_comments,
      response_received_by = auth.uid()
  where id = p_valuation_id
  returning * into v_val;

  perform public.log_audit(
    v_val.organization_id, 'client_valuation.certified', 'client_valuation', v_val.id, null, to_jsonb(v_val)
  );
  perform public.emit_domain_event(
    v_val.organization_id,
    case when v_val.status = 'rejected' then 'client_valuation.rejected' else 'client_valuation.certified' end,
    'client_valuation',
    v_val.id,
    jsonb_build_object(
      'valuation_number', v_val.valuation_number,
      'certified_amount', p_certified_amount,
      'rejected_amount', v_rejected,
      'total_claim', v_val.total_claim
    )
  );

  return v_val;
end;
$$;

grant execute on function public.record_client_valuation_certification(uuid, text, numeric, date, text) to authenticated;

-- =============================================================================
-- H. Client invoice issue + immutability
-- =============================================================================

create or replace function public.is_client_invoice_commercially_locked(
  p_status public.client_invoice_status,
  p_issued_at timestamptz
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_issued_at is not null
    or p_status in ('issued', 'partially_paid', 'paid', 'overdue');
$$;

create or replace function public.protect_issued_client_invoice()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    return new;
  end if;

  if public.is_client_invoice_commercially_locked(old.status, old.issued_at) then
    if new.invoice_number is distinct from old.invoice_number
       or new.project_id is distinct from old.project_id
       or new.contract_id is distinct from old.contract_id
       or new.valuation_id is distinct from old.valuation_id
       or new.invoice_date is distinct from old.invoice_date
       or new.due_date is distinct from old.due_date
       or new.currency is distinct from old.currency
       or new.amount is distinct from old.amount
       or new.vat_amount is distinct from old.vat_amount
       or new.total is distinct from old.total
       or new.issued_at is distinct from old.issued_at then
      raise exception 'Issued client invoice is immutable'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists client_invoices_protect_issued on public.client_invoices;
create trigger client_invoices_protect_issued
  before update on public.client_invoices
  for each row execute function public.protect_issued_client_invoice();

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
begin
  select * into v_inv from public.client_invoices where id = p_invoice_id for update;
  if v_inv.id is null then raise exception 'NOT_FOUND'; end if;

  if not public.has_project_permission('client_invoice.issue', v_inv.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_inv.status <> 'draft' then
    raise exception 'CONFLICT';
  end if;

  if v_inv.valuation_id is not null then
    select * into v_val from public.client_valuations where id = v_inv.valuation_id;
    if v_val.status not in ('certified', 'partially_certified') then
      raise exception 'VALIDATION: valuation must be certified before invoice issue'
        using errcode = 'P0001';
    end if;
    v_certified := coalesce(v_val.certified_amount, 0);
    if v_inv.total > v_certified + 0.001 then
      raise exception 'VALIDATION: invoice total exceeds certified amount'
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
      and status in ('certified', 'partially_certified');
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

-- =============================================================================
-- I. Client payment RPC (concurrency-safe)
-- =============================================================================

create or replace function public.can_record_client_payment(p_project_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_organization_member(p_organization_id)
    and (
      public.has_permission('client_payment.record', p_organization_id, 'organization', null)
      or (
        public.can_access_project(p_project_id)
        and public.has_permission('client_payment.record', p_organization_id, 'project', p_project_id)
      )
    );
$$;

grant execute on function public.can_record_client_payment(uuid, uuid) to authenticated;

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
  select * into v_inv from public.client_invoices where id = p_invoice_id for update;
  if v_inv.id is null then raise exception 'NOT_FOUND'; end if;

  if not public.can_record_client_payment(v_inv.project_id, v_inv.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_inv.status not in ('issued', 'partially_paid', 'overdue') then
    raise exception 'CONFLICT';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'VALIDATION';
  end if;

  if p_reference is null or length(trim(p_reference)) = 0 then
    raise exception 'VALIDATION';
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.client_payments
  where client_invoice_id = v_inv.id;

  v_outstanding := v_inv.total - v_paid;

  if p_amount > v_outstanding + 0.001 then
    raise exception 'CLIENT_PAYMENT_EXCEEDS_INVOICE: payment exceeds invoice outstanding amount'
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

-- =============================================================================
-- J. Partial variation approval
-- =============================================================================

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
  v_submitted numeric(18, 2);
  v_new_status public.variation_status;
begin
  select * into v_vo from public.variations where id = p_variation_id for update;
  if v_vo.id is null then raise exception 'NOT_FOUND'; end if;
  if not public.has_project_permission('variation.approve', v_vo.project_id) then
    raise exception 'FORBIDDEN';
  end if;
  if p_approved_amount is null or p_approved_amount < 0 then raise exception 'VALIDATION'; end if;

  v_submitted := coalesce(nullif(v_vo.submitted_amount, 0), v_vo.cost_impact, 0);

  if p_approved_amount <= 0.001 then
    v_new_status := 'rejected';
  elsif p_approved_amount < v_submitted - 0.001 then
    v_new_status := 'partially_approved';
  else
    v_new_status := 'approved';
  end if;

  update public.variations
  set status = v_new_status,
      approved_amount = p_approved_amount,
      approval_date = (timezone('utc', now()))::date
  where id = p_variation_id
  returning * into v_vo;

  if v_new_status in ('approved', 'partially_approved') then
    update public.project_budgets
    set approved_variation_amount = approved_variation_amount + p_approved_amount,
        status = 'revised'
    where project_id = v_vo.project_id;
  end if;

  perform public.log_audit(
    v_vo.organization_id,
    case v_new_status
      when 'partially_approved' then 'variation.partially_approved'
      when 'rejected' then 'variation.rejected'
      else 'variation.approved'
    end,
    'variation',
    v_vo.id,
    null,
    to_jsonb(v_vo)
  );
  perform public.emit_domain_event(
    v_vo.organization_id,
    case v_new_status
      when 'partially_approved' then 'variation.partially_approved'
      when 'rejected' then 'variation.rejected'
      else 'variation.approved'
    end,
    'variation',
    v_vo.id,
    jsonb_build_object(
      'approved_amount', p_approved_amount,
      'submitted_amount', v_submitted,
      'vo_number', v_vo.vo_number
    )
  );

  return v_vo;
end;
$$;

-- =============================================================================
-- K. RBAC — finance_manager full client revenue permissions
-- =============================================================================

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'finance_manager'
  and r.organization_id is null
  and p.key in (
    'client_valuation.create',
    'client_valuation.submit',
    'client_valuation.approve',
    'finance.manage'
  )
on conflict do nothing;

comment on table public.entity_documents is
  'Structured document links for commercial/procurement entities (multi-attachment).';
comment on function public.record_client_payment(uuid, numeric, date, text, public.payment_method) is
  'Records client receipt with invoice row lock (FOR UPDATE) to prevent concurrent over-collection.';
comment on function public.record_client_valuation_certification(uuid, text, numeric, date, text) is
  'External client/consultant certification — separate from internal decide_entity_approval.';
comment on function public.protect_issued_client_invoice() is
  'Blocks commercial field changes when client invoice is issued or post-issue lifecycle.';
