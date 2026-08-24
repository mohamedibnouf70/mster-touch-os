-- Master Touch OS — 027
-- Phase 2 RPCs: register document, revise, apply A–E, issue transmittal, project health.

create or replace function public.register_controlled_document(
  p_organization_id uuid,
  p_project_id uuid,
  p_type_code text,
  p_discipline_code text,
  p_title text,
  p_description text default null,
  p_responsible_engineer_id uuid default null,
  p_confidentiality public.confidentiality_level default 'internal'
)
returns public.documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.documents;
  v_number text;
  v_category text;
  v_discipline_id uuid;
begin
  if not (
    public.has_permission('document_control.register', p_organization_id)
    or public.has_permission('document.upload', p_organization_id)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if not public.can_access_project(p_project_id) then
    raise exception 'FORBIDDEN';
  end if;

  select category_code into v_category
  from public.document_type_codes where code = p_type_code;
  if v_category is null then
    raise exception 'VALIDATION';
  end if;

  select id into v_discipline_id
  from public.engineering_disciplines
  where organization_id = p_organization_id
    and code = upper(p_discipline_code)
    and is_active = true
  limit 1;

  v_number := public.generate_document_number(
    p_organization_id, p_project_id, p_type_code, upper(p_discipline_code)
  );

  insert into public.documents (
    organization_id, project_id, category, type_code, discipline_id,
    document_number, title, description, current_revision, status,
    confidentiality, approval_state, originator_id, responsible_engineer_id,
    uploaded_by, is_register_controlled
  ) values (
    p_organization_id, p_project_id, v_category, p_type_code, v_discipline_id,
    v_number || '-R00', p_title, p_description, 'R00', 'draft',
    p_confidentiality, 'pending', auth.uid(), p_responsible_engineer_id,
    auth.uid(), true
  ) returning * into v_doc;

  perform public.log_audit(
    p_organization_id, 'document.registered', 'document', v_doc.id, null, to_jsonb(v_doc)
  );
  perform public.emit_domain_event(
    p_organization_id, 'document.registered', 'document', v_doc.id,
    jsonb_build_object('document_number', v_doc.document_number, 'type_code', p_type_code)
  );

  return v_doc;
end;
$$;

create or replace function public.create_document_revision(
  p_document_id uuid,
  p_change_description text default null
)
returns public.documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.documents;
  v_next text;
  v_base text;
begin
  select * into v_doc from public.documents where id = p_document_id for update;
  if v_doc.id is null then
    raise exception 'NOT_FOUND';
  end if;

  if not (
    public.has_permission('document_control.revise', v_doc.organization_id)
    or public.has_permission('document.update', v_doc.organization_id)
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if not public.can_access_project(v_doc.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  update public.document_versions
  set is_current = false,
      is_superseded = true,
      superseded_at = timezone('utc', now())
  where document_id = v_doc.id
    and is_current = true;

  v_next := public.next_revision_code(v_doc.current_revision);

  -- Strip trailing -Rxx from document_number base if present
  v_base := regexp_replace(coalesce(v_doc.document_number, ''), '-R[0-9]+$', '');

  update public.documents
  set current_revision = v_next,
      document_number = case
        when v_base = '' then v_doc.document_number
        else v_base || '-' || v_next
      end,
      status = 'draft',
      approval_state = 'pending',
      official_decision = null,
      submission_status = 'not_submitted',
      updated_at = timezone('utc', now())
  where id = v_doc.id
  returning * into v_doc;

  perform public.log_audit(
    v_doc.organization_id, 'document.revised', 'document', v_doc.id,
    jsonb_build_object('change_description', p_change_description),
    to_jsonb(v_doc)
  );
  perform public.emit_domain_event(
    v_doc.organization_id, 'document.revised', 'document', v_doc.id,
    jsonb_build_object('revision', v_next)
  );

  return v_doc;
end;
$$;

create or replace function public.apply_document_approval_decision(
  p_document_id uuid,
  p_official_code text,
  p_comments text default null
)
returns public.documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.documents;
  v_status public.document_status;
  v_submittal public.submittal_status;
  v_shop public.shop_drawing_status;
  v_event text;
begin
  if p_official_code not in ('A', 'B', 'C', 'D', 'E') then
    raise exception 'VALIDATION';
  end if;
  if p_official_code = 'D' and (p_comments is null or length(trim(p_comments)) = 0) then
    raise exception 'VALIDATION';
  end if;

  select * into v_doc from public.documents where id = p_document_id for update;
  if v_doc.id is null then
    raise exception 'NOT_FOUND';
  end if;

  if not public.has_permission('document.approve', v_doc.organization_id)
     and not public.has_permission('approval.approve', v_doc.organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  v_status := case p_official_code
    when 'A' then 'approved'::public.document_status
    when 'B' then 'approved'::public.document_status
    when 'C' then 'rejected'::public.document_status
    when 'D' then 'rejected'::public.document_status
    else 'submitted'::public.document_status
  end;

  update public.documents
  set official_decision = p_official_code,
      approval_state = case p_official_code
        when 'A' then 'approved'
        when 'B' then 'approved_as_noted'
        when 'C' then 'resubmit'
        when 'D' then 'rejected'
        else 'for_information'
      end,
      status = v_status,
      submission_status = 'responded',
      response_at = timezone('utc', now())
  where id = v_doc.id
  returning * into v_doc;

  update public.document_versions
  set approval_result = p_official_code,
      approval_comments = p_comments,
      reviewer_id = auth.uid(),
      reviewed_at = timezone('utc', now())
  where document_id = v_doc.id
    and is_current = true;

  -- Sync type-specific tables
  if v_doc.type_code = 'MAT' then
    v_submittal := case p_official_code
      when 'A' then 'approved'::public.submittal_status
      when 'B' then 'approved_as_noted'::public.submittal_status
      when 'C' then 'resubmit'::public.submittal_status
      when 'D' then 'rejected'::public.submittal_status
      else 'for_information'::public.submittal_status
    end;
    update public.material_submittals
    set status = v_submittal, official_decision = p_official_code, review_comments = p_comments
    where document_id = v_doc.id;
  elsif v_doc.type_code = 'SHD' then
    v_shop := case p_official_code
      when 'A' then 'approved'::public.shop_drawing_status
      when 'B' then 'approved_as_noted'::public.shop_drawing_status
      when 'C' then 'resubmit'::public.shop_drawing_status
      when 'D' then 'rejected'::public.shop_drawing_status
      else 'under_review'::public.shop_drawing_status
    end;
    update public.shop_drawings
    set status = v_shop,
        official_decision = p_official_code,
        approval_comments = p_comments,
        approved_for_execution = (p_official_code in ('A', 'B'))
    where document_id = v_doc.id;
  elsif v_doc.type_code = 'MS' then
    update public.method_statements
    set official_decision = p_official_code,
        status = case p_official_code
          when 'A' then 'approved_for_use'::public.method_statement_status
          when 'B' then 'approved_as_noted'::public.method_statement_status
          when 'C' then 'resubmit'::public.method_statement_status
          when 'D' then 'rejected'::public.method_statement_status
          else 'under_review'::public.method_statement_status
        end
    where document_id = v_doc.id;
  end if;

  v_event := case p_official_code
    when 'A' then 'document.approved'
    when 'B' then 'document.approved'
    when 'C' then 'document.resubmit_required'
    when 'D' then 'document.rejected'
    else 'document.approved'
  end;

  perform public.log_audit(
    v_doc.organization_id, v_event, 'document', v_doc.id, null,
    jsonb_build_object('official_code', p_official_code, 'comments', p_comments)
  );
  perform public.emit_domain_event(
    v_doc.organization_id, v_event, 'document', v_doc.id,
    jsonb_build_object('official_code', p_official_code)
  );

  return v_doc;
end;
$$;

create or replace function public.issue_transmittal(p_transmittal_id uuid)
returns public.transmittals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trn public.transmittals;
  v_count integer;
begin
  select * into v_trn from public.transmittals where id = p_transmittal_id for update;
  if v_trn.id is null then
    raise exception 'NOT_FOUND';
  end if;
  if v_trn.status <> 'draft' then
    raise exception 'CONFLICT';
  end if;
  if not public.has_project_permission('transmittal.issue', v_trn.project_id) then
    raise exception 'FORBIDDEN';
  end if;

  select count(*) into v_count from public.transmittal_items where transmittal_id = v_trn.id;
  if v_count = 0 then
    raise exception 'VALIDATION';
  end if;

  update public.transmittals
  set status = 'issued',
      issued_by = auth.uid(),
      issued_date = (timezone('utc', now()))::date,
      issued_at = timezone('utc', now())
  where id = v_trn.id
  returning * into v_trn;

  perform public.log_audit(
    v_trn.organization_id, 'transmittal.issued', 'transmittal', v_trn.id, null, to_jsonb(v_trn)
  );
  perform public.emit_domain_event(
    v_trn.organization_id, 'transmittal.issued', 'transmittal', v_trn.id,
    jsonb_build_object('item_count', v_count)
  );

  return v_trn;
end;
$$;

create or replace function public.compute_project_health(p_project_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_overdue_rfi integer := 0;
  v_overdue_docs integer := 0;
  v_open_ncr integer := 0;
  v_critical_ncr integer := 0;
  v_failed_ir integer := 0;
  v_late_stages integer := 0;
  v_resubmit integer := 0;
begin
  select organization_id into v_org from public.projects where id = p_project_id;
  if v_org is null then
    return 'green';
  end if;

  select count(*) into v_overdue_rfi from public.rfis
  where project_id = p_project_id
    and status in ('submitted', 'under_review')
    and response_required_by is not null
    and response_required_by < timezone('utc', now());

  select count(*) into v_overdue_docs from public.documents
  where project_id = p_project_id
    and submission_status in ('submitted', 'under_review')
    and response_due_at is not null
    and response_due_at < timezone('utc', now());

  select count(*) into v_open_ncr from public.ncrs
  where project_id = p_project_id and status not in ('closed');

  select count(*) into v_critical_ncr from public.ncrs
  where project_id = p_project_id and severity = 'critical' and status not in ('closed');

  select count(*) into v_failed_ir from public.inspection_requests
  where project_id = p_project_id and status in ('failed', 'reinspection_required');

  select count(*) into v_late_stages from public.project_stages
  where project_id = p_project_id
    and status in ('in_progress', 'not_started')
    and planned_end is not null
    and planned_end < (timezone('utc', now()))::date;

  select count(*) into v_resubmit from public.documents
  where project_id = p_project_id and official_decision = 'C';

  if v_critical_ncr > 0 or v_overdue_rfi >= 5 or v_failed_ir >= 3 then
    return 'red';
  end if;

  if v_open_ncr > 0 or v_overdue_rfi > 0 or v_overdue_docs > 0
     or v_late_stages > 0 or v_resubmit > 0 or v_failed_ir > 0 then
    return 'amber';
  end if;

  return 'green';
end;
$$;

grant execute on function public.register_controlled_document(uuid, uuid, text, text, text, text, uuid, public.confidentiality_level) to authenticated;
grant execute on function public.create_document_revision(uuid, text) to authenticated;
grant execute on function public.apply_document_approval_decision(uuid, text, text) to authenticated;
grant execute on function public.issue_transmittal(uuid) to authenticated;
grant execute on function public.compute_project_health(uuid) to authenticated;
