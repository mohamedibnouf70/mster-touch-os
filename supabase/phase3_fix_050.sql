-- Master Touch OS — phase3_fix_050
-- Apply this file in the Supabase Dashboard SQL Editor.
-- Equivalent to migrations/050_phase32_live_hardening.sql
-- Do NOT re-run 049. Do NOT modify 001–049.
--
-- ROOT CAUSES addressed:
-- 1) has_project_permission requires can_access_project → org-scoped finance FORBIDDEN
-- 2) finance_manager lacked project.read_all in DB (catalog already had it)
-- 3) Payment CONFLICT cascaded from failed issue (draft invoice)
-- 4) client_invoices RLS silent 0-row UPDATE skipped immutability trigger
-- 5) Generic CONFLICT / FORBIDDEN hid business validation errors

-- Master Touch OS — 050
-- Phase 3.2 live hardening after 049:
-- ROOT CAUSES (proven against live Phase 3.2 failures):
-- 1) Certification / issue / variation RPCs used has_project_permission which
--    requires can_access_project. Org-scoped finance roles have no project
--    membership and lacked project.read_all → FORBIDDEN (same pattern as 046
--    supplier payment). beforeAll ignored certification failure → certified_amount=0.
-- 2) Live fixture used finance_officer (no client_invoice.issue / variation.approve /
--    client_valuation.approve). finance_manager is the intended commercial role.
-- 3) Payment CONFLICT was cascading: invoice stayed draft because issue failed;
--    record_client_payment used generic CONFLICT for non-payable status.
-- 4) client_invoices UPDATE RLS short-circuited before immutability trigger
--    (0 rows, no error) — same class of bug as issued PO/transmittal.
-- 5) finance_manager catalog includes project.read_all but DB seed did not.

-- =============================================================================
-- A. Org-scoped authorization helpers (mirror can_record_supplier_payment / 046)
-- =============================================================================

create or replace function public.can_issue_client_invoice(p_project_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_organization_member(p_organization_id)
    and (
      public.has_permission('client_invoice.issue', p_organization_id, 'organization', null)
      or (
        public.can_access_project(p_project_id)
        and public.has_permission('client_invoice.issue', p_organization_id, 'project', p_project_id)
      )
    );
$$;

grant execute on function public.can_issue_client_invoice(uuid, uuid) to authenticated;

create or replace function public.can_certify_client_valuation(p_project_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_organization_member(p_organization_id)
    and (
      public.has_permission('client_valuation.approve', p_organization_id, 'organization', null)
      or public.has_permission('finance.manage', p_organization_id, 'organization', null)
      or (
        public.can_access_project(p_project_id)
        and (
          public.has_permission('client_valuation.approve', p_organization_id, 'project', p_project_id)
          or public.has_permission('finance.manage', p_organization_id, 'project', p_project_id)
        )
      )
    );
$$;

grant execute on function public.can_certify_client_valuation(uuid, uuid) to authenticated;

create or replace function public.can_approve_variation(p_project_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_organization_member(p_organization_id)
    and (
      public.has_permission('variation.approve', p_organization_id, 'organization', null)
      or (
        public.can_access_project(p_project_id)
        and public.has_permission('variation.approve', p_organization_id, 'project', p_project_id)
      )
    );
$$;

grant execute on function public.can_approve_variation(uuid, uuid) to authenticated;

create or replace function public.can_write_client_invoice_row(p_project_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_organization_member(p_organization_id)
    and (
      public.has_permission('client_invoice.create', p_organization_id, 'organization', null)
      or public.has_permission('client_invoice.issue', p_organization_id, 'organization', null)
      or (
        public.can_access_project(p_project_id)
        and (
          public.has_permission('client_invoice.create', p_organization_id, 'project', p_project_id)
          or public.has_permission('client_invoice.issue', p_organization_id, 'project', p_project_id)
        )
      )
    );
$$;

grant execute on function public.can_write_client_invoice_row(uuid, uuid) to authenticated;

-- =============================================================================
-- B. RBAC — finance_manager project.read_all + valuation lifecycle (idempotent)
-- =============================================================================

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'finance_manager'
  and r.organization_id is null
  and p.key in (
    'project.read_all',
    'client_valuation.create',
    'client_valuation.submit',
    'client_valuation.approve'
  )
on conflict do nothing;

-- =============================================================================
-- C. External client certification (preserve submitted claim; org-scoped auth)
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
  v_submitted numeric(18, 2);
  v_rejected numeric(18, 2);
  v_cert_date date := coalesce(p_certification_date, (timezone('utc', now()))::date);
begin
  select * into v_val from public.client_valuations where id = p_valuation_id for update;
  if v_val.id is null then
    raise exception 'CLIENT_VALUATION_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  if not public.can_certify_client_valuation(v_val.project_id, v_val.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_val.status not in ('submitted', 'under_client_review') then
    raise exception 'CLIENT_VALUATION_NOT_CERTIFIABLE: status must be submitted or under_client_review'
      using errcode = 'P0001';
  end if;

  if p_certified_amount is null or p_certified_amount < 0 then
    raise exception 'VALIDATION';
  end if;

  -- Preserve submitted claim (total_claim / current_claim_amount) permanently.
  v_submitted := coalesce(v_val.total_claim, 0);

  if p_certified_amount > v_submitted + 0.001 then
    raise exception 'CLIENT_CERTIFICATION_EXCEEDS_CLAIM: certified amount exceeds submitted claim'
      using errcode = 'P0001';
  end if;

  v_rejected := round(v_submitted - p_certified_amount, 2);

  update public.client_valuations
  set status = case
        when p_certified_amount <= 0.001 then 'rejected'::public.valuation_status
        when p_certified_amount < v_submitted - 0.001 then 'partially_certified'::public.valuation_status
        else 'certified'::public.valuation_status
      end,
      client_reference = p_client_reference,
      certified_amount = p_certified_amount,
      rejected_amount = v_rejected,
      certification_date = v_cert_date,
      certification_comments = p_comments,
      response_received_by = auth.uid()
      -- intentionally do NOT touch: total_claim, current_claim_amount, gross_work_value, etc.
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
      'total_claim', v_submitted
    )
  );

  return v_val;
end;
$$;

-- =============================================================================
-- D. Issue client invoice (org-scoped auth + certified remaining capacity)
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
    if v_val.status not in ('certified', 'partially_certified') then
      raise exception 'CLIENT_VALUATION_NOT_CERTIFIED: valuation must be certified before invoice issue'
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

-- =============================================================================
-- E. Client payment — stable domain errors (preserve FOR UPDATE lock)
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
  select * into v_inv from public.client_invoices where id = p_invoice_id for update;
  if v_inv.id is null then
    raise exception 'CLIENT_INVOICE_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  if not public.can_record_client_payment(v_inv.project_id, v_inv.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  if v_inv.status not in ('issued', 'partially_paid', 'overdue') then
    raise exception 'CLIENT_INVOICE_NOT_PAYABLE: invoice must be issued, partially_paid, or overdue'
      using errcode = 'P0001';
  end if;

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

  select coalesce(sum(amount), 0) into v_paid
  from public.client_payments
  where client_invoice_id = v_inv.id;

  v_outstanding := v_inv.total - v_paid;

  if p_amount > v_outstanding + 0.001 then
    raise exception 'CLIENT_PAYMENT_EXCEEDS_OUTSTANDING: payment exceeds invoice outstanding amount'
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

-- =============================================================================
-- F. Partial variation approval — org-scoped auth
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

  if not public.can_approve_variation(v_vo.project_id, v_vo.organization_id) then
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
-- G. client_invoices RLS — allow authorized UPDATE to reach immutability trigger
-- ROOT CAUSE: FOR ALL + has_project_permission requires can_access_project;
-- org-scoped finance matched 0 rows → silent PostgREST success, trigger never ran.
-- =============================================================================

drop policy if exists client_invoices_write on public.client_invoices;
drop policy if exists client_invoices_select on public.client_invoices;
drop policy if exists client_invoices_insert on public.client_invoices;
drop policy if exists client_invoices_update on public.client_invoices;
drop policy if exists client_invoices_delete on public.client_invoices;

create policy client_invoices_select on public.client_invoices
  for select to authenticated
  using (
    public.is_organization_member(organization_id)
    and (
      public.has_permission('client_invoice.read', organization_id, 'organization', null)
      or public.has_permission('finance.read', organization_id, 'organization', null)
      or (
        public.can_access_project(project_id)
        and public.has_permission('client_invoice.read', organization_id, 'project', project_id)
      )
    )
  );

create policy client_invoices_insert on public.client_invoices
  for insert to authenticated
  with check (
    public.is_organization_member(organization_id)
    and (
      public.has_permission('client_invoice.create', organization_id, 'organization', null)
      or (
        public.can_access_project(project_id)
        and public.has_permission('client_invoice.create', organization_id, 'project', project_id)
      )
    )
  );

create policy client_invoices_update on public.client_invoices
  for update to authenticated
  using (public.can_write_client_invoice_row(project_id, organization_id))
  with check (public.can_write_client_invoice_row(project_id, organization_id));

create policy client_invoices_delete on public.client_invoices
  for delete to authenticated
  using (
    public.is_organization_member(organization_id)
    and (
      public.has_permission('client_invoice.create', organization_id, 'organization', null)
      or (
        public.can_access_project(project_id)
        and public.has_permission('client_invoice.create', organization_id, 'project', project_id)
      )
    )
  );

-- =============================================================================
-- H. recalculate must not overwrite submitted/certified commercial history
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

  if v_val.status not in ('draft', 'internal_review') then
    raise exception 'CLIENT_VALUATION_LOCKED: cannot recalculate after submission/certification'
      using errcode = 'P0001';
  end if;

  if not public.has_project_permission('client_valuation.create', v_val.project_id)
     and not public.has_project_permission('client_valuation.submit', v_val.project_id)
     and not public.has_project_permission('finance.manage', v_val.project_id)
     and not public.has_permission('client_valuation.create', v_val.organization_id, 'organization', null)
     and not public.has_permission('finance.manage', v_val.organization_id, 'organization', null) then
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

comment on function public.can_issue_client_invoice(uuid, uuid) is
  'Org-scoped client_invoice.issue for finance, or project-scoped with can_access_project.';
comment on function public.can_certify_client_valuation(uuid, uuid) is
  'Org-scoped client_valuation.approve / finance.manage, or project-scoped equivalent.';
comment on function public.can_approve_variation(uuid, uuid) is
  'Org-scoped variation.approve for finance/commercial, or project-scoped with can_access_project.';
comment on function public.protect_issued_client_invoice() is
  'Blocks commercial field changes when client invoice is issued. Requires RLS UPDATE to reach trigger.';
comment on function public.recalculate_client_valuation(uuid) is
  'Authoritative draft/internal_review totals only. Never runs after certification.';
