-- Master Touch OS — resume Phase 2 from migration 028 (after 015–027 already applied)
-- Run phase2_verify.sql first.

-- Master Touch OS — 028
-- Phase 2 indexes, workflow seeds, health helper views/notes.

create extension if not exists pg_trgm;

-- Additional operational indexes
create index if not exists documents_register_idx
  on public.documents (organization_id, is_register_controlled, type_code, created_at desc)
  where is_register_controlled = true;

create index if not exists documents_search_trgm_idx
  on public.documents using gin (document_number gin_trgm_ops);

create index if not exists documents_title_trgm_idx
  on public.documents using gin (title gin_trgm_ops);

create index if not exists rfis_number_trgm_idx
  on public.rfis using gin (rfi_number gin_trgm_ops);

create index if not exists material_submittals_number_trgm_idx
  on public.material_submittals using gin (mat_number gin_trgm_ops);

create index if not exists shop_drawings_number_trgm_idx
  on public.shop_drawings using gin (shd_number gin_trgm_ops);

create index if not exists ncrs_number_trgm_idx
  on public.ncrs using gin (ncr_number gin_trgm_ops);

create index if not exists transmittals_number_trgm_idx
  on public.transmittals using gin (transmittal_number gin_trgm_ops);

-- Seed Phase 2 document workflows (versioned)
-- NOTE: Phase 1 (013) already uses definition id ...000001 for document_approval.
-- Phase 2 RFI uses ...000010 to avoid (definition_id, version_number) collision.
insert into public.workflow_definitions (
  id, organization_id, code, name_ar, name_en, entity_type, status
) values
  ('40000000-0000-0000-0000-000000000010', null, 'rfi_lifecycle', 'دورة طلب الاستفسار', 'RFI Lifecycle', 'rfi', 'published'),
  ('40000000-0000-0000-0000-000000000002', null, 'submittal_lifecycle', 'دورة اعتماد المواد', 'Material Submittal Lifecycle', 'material_submittal', 'published'),
  ('40000000-0000-0000-0000-000000000003', null, 'shop_drawing_lifecycle', 'دورة المخطط التنفيذي', 'Shop Drawing Lifecycle', 'shop_drawing', 'published'),
  ('40000000-0000-0000-0000-000000000004', null, 'method_statement_lifecycle', 'دورة طريقة التنفيذ', 'Method Statement Lifecycle', 'method_statement', 'published')
on conflict (id) do nothing;

-- Ensure rfi_lifecycle exists even if id ...000001 was taken by Phase 1 document_approval
insert into public.workflow_definitions (id, organization_id, code, name_ar, name_en, entity_type, status)
select
  '40000000-0000-0000-0000-000000000010',
  null,
  'rfi_lifecycle',
  'دورة طلب الاستفسار',
  'RFI Lifecycle',
  'rfi',
  'published'::public.workflow_definition_status
where not exists (
  select 1 from public.workflow_definitions where code = 'rfi_lifecycle'
);

insert into public.workflow_versions (id, definition_id, version_number, status, published_at)
values
  ('40000000-0000-0000-0000-000000000011', '40000000-0000-0000-0000-000000000010', 1, 'published', timezone('utc', now())),
  ('40000000-0000-0000-0000-000000000012', '40000000-0000-0000-0000-000000000002', 1, 'published', timezone('utc', now())),
  ('40000000-0000-0000-0000-000000000013', '40000000-0000-0000-0000-000000000003', 1, 'published', timezone('utc', now())),
  ('40000000-0000-0000-0000-000000000014', '40000000-0000-0000-0000-000000000004', 1, 'published', timezone('utc', now()))
on conflict (definition_id, version_number) do nothing;

-- RFI steps
insert into public.workflow_steps (version_id, key, name_ar, name_en, sequence, assignee_type, requires_approval, on_resubmit_step_key)
select '40000000-0000-0000-0000-000000000011', s.key, s.name_ar, s.name_en, s.sequence, s.assignee_type::public.assignee_type, s.requires_approval, s.on_resubmit
from (values
  ('draft', 'مسودة', 'Draft', 1, 'unassigned', false, null),
  ('internal_review', 'مراجعة داخلية', 'Internal Review', 2, 'role', true, 'draft'),
  ('submit', 'تقديم', 'Submit', 3, 'role', false, null),
  ('external_review', 'مراجعة خارجية', 'External Review', 4, 'role', true, 'draft'),
  ('close', 'إغلاق', 'Close', 5, 'role', false, null)
) as s(key, name_ar, name_en, sequence, assignee_type, requires_approval, on_resubmit)
where not exists (
  select 1 from public.workflow_steps ws
  where ws.version_id = '40000000-0000-0000-0000-000000000011' and ws.key = s.key
);

-- Submittal / Shop drawing shared pattern
insert into public.workflow_steps (version_id, key, name_ar, name_en, sequence, assignee_type, requires_approval, on_resubmit_step_key)
select v.version_id, s.key, s.name_ar, s.name_en, s.sequence, s.assignee_type::public.assignee_type, s.requires_approval, s.on_resubmit
from (values
  ('40000000-0000-0000-0000-000000000012'::uuid),
  ('40000000-0000-0000-0000-000000000013'::uuid)
) as v(version_id)
cross join (values
  ('prepare', 'إعداد', 'Prepare', 1, 'unassigned', false, null),
  ('eng_review', 'مراجعة هندسية', 'Engineering Review', 2, 'role', true, 'prepare'),
  ('pm_review', 'مراجعة مدير المشروع', 'PM Review', 3, 'project_manager', true, 'prepare'),
  ('dc_register', 'تسجيل مراقبة الوثائق', 'Document Control', 4, 'role', false, null),
  ('external', 'مراجعة استشاري/عميل', 'External Review', 5, 'role', true, 'prepare')
) as s(key, name_ar, name_en, sequence, assignee_type, requires_approval, on_resubmit)
where not exists (
  select 1 from public.workflow_steps ws
  where ws.version_id = v.version_id and ws.key = s.key
);

-- Method statement with HSE/QA gates
insert into public.workflow_steps (version_id, key, name_ar, name_en, sequence, assignee_type, requires_approval, on_resubmit_step_key)
select '40000000-0000-0000-0000-000000000014', s.key, s.name_ar, s.name_en, s.sequence, s.assignee_type::public.assignee_type, s.requires_approval, s.on_resubmit
from (values
  ('prepare', 'إعداد', 'Prepare', 1, 'unassigned', false, null),
  ('eng_review', 'مراجعة هندسية', 'Engineering Review', 2, 'role', true, 'prepare'),
  ('hse_review', 'مراجعة السلامة', 'HSE Review', 3, 'role', true, 'prepare'),
  ('qa_review', 'مراجعة الجودة', 'Quality Review', 4, 'role', true, 'prepare'),
  ('pm_review', 'مراجعة مدير المشروع', 'PM Review', 5, 'project_manager', true, 'prepare'),
  ('external', 'تقديم واعتماد', 'External Approval', 6, 'role', true, 'prepare')
) as s(key, name_ar, name_en, sequence, assignee_type, requires_approval, on_resubmit)
where not exists (
  select 1 from public.workflow_steps ws
  where ws.version_id = '40000000-0000-0000-0000-000000000014' and ws.key = s.key
);

-- Document health rules (documented in compute_project_health):
-- RED: any critical open NCR OR overdue RFI >= 5 OR failed IR >= 3
-- AMBER: any open NCR / overdue RFI or approval / late stage / resubmit pending / failed IR
-- GREEN: otherwise
comment on function public.compute_project_health(uuid) is
  'Deterministic project health: green|amber|red based on overdue RFIs/approvals, open/critical NCRs, failed inspections, late stages, resubmit documents.';


-- Master Touch OS — 029
-- Patch: create R00 version on register; insert version on revise;
-- allow type-specific create permissions for register_controlled_document.

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
  v_perm text;
begin
  v_perm := case p_type_code
    when 'RFI' then 'rfi.create'
    when 'MAT' then 'submittal.create'
    when 'SHD' then 'shop_drawing.create'
    when 'MS' then 'method_statement.create'
    when 'IR' then 'inspection.create'
    when 'NCR' then 'ncr.create'
    when 'COR' then 'correspondence.create'
    when 'TRN' then 'transmittal.create'
    when 'RPT' then 'report.create'
    else null
  end;

  if not (
    public.has_permission('document_control.register', p_organization_id)
    or public.has_permission('document.upload', p_organization_id)
    or (v_perm is not null and public.has_permission(v_perm, p_organization_id))
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

  -- Placeholder current revision (file attached later via storage upload)
  insert into public.document_versions (
    organization_id, document_id, revision, file_path, file_name, mime_type, size_bytes,
    uploaded_by, is_current, is_superseded, change_description, submitted_by
  ) values (
    p_organization_id,
    v_doc.id,
    'R00',
    format('org/%s/project/%s/documents/%s/R00.placeholder', p_organization_id, p_project_id, v_doc.id),
    'R00.placeholder',
    'application/octet-stream',
    0,
    auth.uid(),
    true,
    false,
    'Initial controlled registration',
    auth.uid()
  );

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

  insert into public.document_versions (
    organization_id, document_id, revision, file_path, file_name, mime_type, size_bytes,
    uploaded_by, is_current, is_superseded, change_description, submitted_by
  ) values (
    v_doc.organization_id,
    v_doc.id,
    v_next,
    format('org/%s/project/%s/documents/%s/%s.placeholder', v_doc.organization_id, v_doc.project_id, v_doc.id, v_next),
    v_next || '.placeholder',
    'application/octet-stream',
    0,
    auth.uid(),
    true,
    false,
    p_change_description,
    auth.uid()
  );

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

grant execute on function public.register_controlled_document(uuid, uuid, text, text, text, text, uuid, public.confidentiality_level) to authenticated;
grant execute on function public.create_document_revision(uuid, text) to authenticated;

