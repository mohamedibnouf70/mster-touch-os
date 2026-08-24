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
