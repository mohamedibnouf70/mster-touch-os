-- Master Touch OS — Phase 2 apply verification
-- Run in Supabase SQL Editor after partial or full apply.

-- 1) Which Phase 2 tables exist?
select
  t.table_name,
  case when t.table_name is not null then 'yes' else 'no' end as exists
from (
  values
    ('engineering_disciplines'),
    ('project_disciplines'),
    ('document_type_codes'),
    ('document_number_counters'),
    ('rfis'),
    ('material_submittals'),
    ('shop_drawings'),
    ('method_statements'),
    ('inspection_requests'),
    ('ncrs'),
    ('project_reports'),
    ('correspondence'),
    ('project_contacts'),
    ('transmittals'),
    ('transmittal_items')
) as expected(name)
left join information_schema.tables t
  on t.table_schema = 'public'
 and t.table_name = expected.name
order by expected.name;

-- 2) Phase 2 RPCs present?
select p.proname as rpc_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'generate_document_number',
    'register_controlled_document',
    'create_document_revision',
    'apply_document_approval_decision',
    'issue_transmittal',
    'compute_project_health',
    'has_project_permission'
  )
order by p.proname;

-- 3) Engineering disciplines seeded (Master Touch org)?
select code, name_en, is_active
from public.engineering_disciplines
where organization_id = '11111111-1111-1111-1111-111111111111'
order by code;

-- 4) Phase 2 permissions seeded?
select key
from public.permissions
where key in ('project.read_all', 'rfi.create', 'document_control.register', 'transmittal.issue')
order by key;

-- 5) Workflow definitions — Phase 1 vs Phase 2 (check UUID collision resolved)
select id, code, entity_type, status
from public.workflow_definitions
where id in (
  '40000000-0000-0000-0000-000000000001', -- Phase 1 document_approval
  '40000000-0000-0000-0000-000000000010', -- Phase 2 rfi_lifecycle (fixed)
  '40000000-0000-0000-0000-000000000002',
  '40000000-0000-0000-0000-000000000003',
  '40000000-0000-0000-0000-000000000004'
)
or code in ('rfi_lifecycle', 'submittal_lifecycle', 'shop_drawing_lifecycle', 'method_statement_lifecycle', 'document_approval')
order by code;

-- 6) Workflow versions for Phase 2 definitions
select wd.code, wv.id as version_id, wv.version_number, wv.status,
       (select count(*) from public.workflow_steps ws where ws.version_id = wv.id) as step_count
from public.workflow_definitions wd
join public.workflow_versions wv on wv.definition_id = wd.id
where wd.code in ('rfi_lifecycle', 'submittal_lifecycle', 'shop_drawing_lifecycle', 'method_statement_lifecycle', 'document_approval')
order by wd.code, wv.version_number;

-- 7) Detect partial-apply failure signature (028 failed before fix)
-- Phase 1 version on document_approval + missing rfi_lifecycle definition
select
  exists (
    select 1 from public.workflow_definitions where id = '40000000-0000-0000-0000-000000000001' and code = 'document_approval'
  ) as phase1_document_approval_ok,
  exists (
    select 1 from public.workflow_definitions where code = 'rfi_lifecycle'
  ) as rfi_lifecycle_exists,
  exists (
    select 1 from public.workflow_versions
    where definition_id = '40000000-0000-0000-0000-000000000002' and version_number = 1
  ) as submittal_v1_exists,
  exists (
    select 1 from public.rfis
  ) as any_rfis;

-- 8) Optional tracking table (if apply-phase2 script was used)
select filename, applied_at
from public.schema_migrations
where filename like '0%'
order by applied_at;
