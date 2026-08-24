-- Master Touch OS — Phase 2 apply (015–029)
-- Safe to re-run AFTER a partial apply when using fixed migration 028 (workflow UUID collision resolved).
-- For resume after failure at 028: run supabase/phase2_resume_028_029.sql instead.
-- Verify state first: supabase/phase2_verify.sql


-- ===== 015_engineering_disciplines.sql =====

-- Master Touch OS — 015
-- Engineering disciplines and project discipline activation.

create table public.engineering_disciplines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create trigger engineering_disciplines_set_updated_at
  before update on public.engineering_disciplines
  for each row execute function public.set_updated_at();

create index engineering_disciplines_org_idx
  on public.engineering_disciplines (organization_id, is_active);

create table public.project_disciplines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  discipline_id uuid not null references public.engineering_disciplines (id) on delete restrict,
  is_active boolean not null default true,
  activated_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  unique (project_id, discipline_id)
);

create index project_disciplines_project_idx
  on public.project_disciplines (project_id, is_active);

-- Seed Master Touch organization disciplines
insert into public.engineering_disciplines (organization_id, code, name_ar, name_en, description)
select
  '11111111-1111-1111-1111-111111111111',
  d.code,
  d.name_ar,
  d.name_en,
  d.description
from (values
  ('ARCH', 'العمارة / التصميم الداخلي', 'Architecture / Interior', 'Architecture and interior design'),
  ('ELEC', 'الكهرباء', 'Electrical', 'Electrical systems'),
  ('SMART', 'الأنظمة الذكية', 'Smart Systems', 'Smart and low-voltage systems'),
  ('PLUM', 'السباكة', 'Plumbing', 'Plumbing and drainage'),
  ('HVAC', 'التكييف والتهوية', 'HVAC', 'Heating, ventilation and air conditioning'),
  ('MECH', 'الميكانيكا', 'Mechanical', 'Mechanical systems'),
  ('FIRE', 'مكافحة الحريق', 'Fire Fighting', 'Fire protection systems'),
  ('CIVIL', 'المدني', 'Civil', 'Civil works'),
  ('STRUCT', 'الإنشائي', 'Structural', 'Structural engineering'),
  ('GENERAL', 'عام', 'General', 'General / multi-discipline')
) as d(code, name_ar, name_en, description)
on conflict (organization_id, code) do nothing;


-- ===== 016_document_control.sql =====

-- Master Touch OS — 016
-- Document control register metadata, R00 revisions, concurrency-safe numbering.

-- Controlled document type codes used in numbering (extends categories)
create table if not exists public.document_type_codes (
  code text primary key,
  category_code text not null references public.document_categories (code),
  name_ar text not null,
  name_en text not null,
  abbreviation text not null,
  is_formal boolean not null default true
);

insert into public.document_type_codes (code, category_code, name_ar, name_en, abbreviation, is_formal) values
  ('RFI', 'rfi', 'طلب استفسار فني', 'Request for Information', 'RFI', true),
  ('MAT', 'material_submittal', 'طلب اعتماد مواد', 'Material Submittal', 'MAT', true),
  ('SHD', 'shop_drawing', 'مخطط تنفيذي', 'Shop Drawing', 'SHD', true),
  ('MS', 'method_statement', 'طريقة تنفيذ', 'Method Statement', 'MS', true),
  ('IR', 'inspection_request', 'طلب فحص', 'Inspection Request', 'IR', true),
  ('NCR', 'ncr', 'تقرير عدم مطابقة', 'Non-Conformance Report', 'NCR', true),
  ('RPT', 'other', 'تقرير مشروع', 'Project Report', 'RPT', true),
  ('COR', 'other', 'مراسلات', 'Correspondence', 'COR', true),
  ('TRN', 'other', 'إرسالية مستندات', 'Transmittal', 'TRN', true),
  ('RFA', 'other', 'طلب موافقة', 'Request for Approval', 'RFA', true),
  ('ABD', 'drawing', 'مخطط كما نُفذ', 'As-Built Drawing', 'ABD', true),
  ('TS', 'other', 'تقديم فني', 'Technical Submittal', 'TS', true),
  ('HO', 'handover', 'مستند تسليم', 'Handover Document', 'HO', true),
  ('WAR', 'warranty', 'ضمان', 'Warranty', 'WAR', true),
  ('OM', 'other', 'دليل التشغيل والصيانة', 'O&M Manual', 'OM', true)
on conflict (code) do nothing;

create table public.document_number_counters (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  type_code text not null references public.document_type_codes (code),
  discipline_code text not null,
  next_value integer not null default 1,
  primary key (organization_id, project_id, type_code, discipline_code)
);

-- Extend documents for formal register
alter table public.documents
  add column if not exists type_code text references public.document_type_codes (code),
  add column if not exists discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  add column if not exists description text,
  add column if not exists originator_id uuid references public.profiles (id) on delete set null,
  add column if not exists responsible_engineer_id uuid references public.profiles (id) on delete set null,
  add column if not exists submission_status text not null default 'not_submitted'
    check (submission_status in (
      'not_submitted', 'ready', 'submitted', 'under_review', 'responded', 'closed'
    )),
  add column if not exists official_decision text
    check (official_decision is null or official_decision in ('A', 'B', 'C', 'D', 'E')),
  add column if not exists submitted_at timestamptz,
  add column if not exists response_due_at timestamptz,
  add column if not exists response_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists external_reference text,
  add column if not exists workflow_instance_id uuid references public.workflow_instances (id) on delete set null,
  add column if not exists approval_request_id uuid references public.approval_requests (id) on delete set null,
  add column if not exists is_register_controlled boolean not null default false;

create unique index if not exists documents_org_number_uidx
  on public.documents (organization_id, document_number)
  where document_number is not null;

create index if not exists documents_type_idx on public.documents (organization_id, type_code);
create index if not exists documents_discipline_idx on public.documents (discipline_id);
create index if not exists documents_responsible_idx on public.documents (responsible_engineer_id);
create index if not exists documents_response_due_idx on public.documents (response_due_at, submission_status);
create index if not exists documents_decision_idx on public.documents (official_decision);

-- Extend document_versions for controlled revision metadata
alter table public.document_versions
  add column if not exists change_description text,
  add column if not exists is_current boolean not null default false,
  add column if not exists is_superseded boolean not null default false,
  add column if not exists superseded_at timestamptz,
  add column if not exists approval_result text
    check (approval_result is null or approval_result in ('A', 'B', 'C', 'D', 'E')),
  add column if not exists approval_comments text,
  add column if not exists reviewer_id uuid references public.profiles (id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists submitted_by uuid references public.profiles (id) on delete set null,
  add column if not exists submitted_at timestamptz;

-- Ensure at most one current revision per document
create unique index if not exists document_versions_one_current_uidx
  on public.document_versions (document_id)
  where is_current = true;

create or replace function public.next_revision_code(p_current text)
returns text
language plpgsql
immutable
as $$
declare
  v_num integer;
begin
  if p_current is null or p_current = '' then
    return 'R00';
  end if;
  if p_current ~ '^R[0-9]+$' then
    v_num := substring(p_current from 2)::integer + 1;
    return 'R' || lpad(v_num::text, 2, '0');
  end if;
  -- Legacy letter revision A/B/C → map to R01+ after first formal bump
  if length(p_current) = 1 and p_current ~ '^[A-Za-z]$' then
    return 'R01';
  end if;
  return 'R00';
end;
$$;

create or replace function public.generate_document_number(
  p_organization_id uuid,
  p_project_id uuid,
  p_type_code text,
  p_discipline_code text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text;
  v_project_code text;
  v_abbr text;
  v_value integer;
  v_number text;
begin
  if not public.is_organization_member(p_organization_id) then
    raise exception 'FORBIDDEN';
  end if;

  select project_code into v_project_code
  from public.projects
  where id = p_project_id and organization_id = p_organization_id;

  if v_project_code is null then
    raise exception 'NOT_FOUND';
  end if;

  select abbreviation into v_abbr
  from public.document_type_codes
  where code = p_type_code;

  if v_abbr is null then
    raise exception 'VALIDATION';
  end if;

  insert into public.document_number_counters (
    organization_id, project_id, type_code, discipline_code, next_value
  ) values (
    p_organization_id, p_project_id, p_type_code, upper(p_discipline_code), 1
  )
  on conflict (organization_id, project_id, type_code, discipline_code) do update
    set next_value = public.document_number_counters.next_value + 1
  returning next_value into v_value;

  v_number := format(
    'MT-%s-%s-%s-%s',
    v_project_code,
    v_abbr,
    upper(p_discipline_code),
    lpad(v_value::text, 4, '0')
  );

  return v_number;
end;
$$;

grant execute on function public.generate_document_number(uuid, uuid, text, text) to authenticated;
grant execute on function public.next_revision_code(text) to authenticated;


-- ===== 017_rfi.sql =====

-- Master Touch OS — 017
-- RFI (Request for Information) module.

create type public.rfi_status as enum (
  'draft',
  'internal_review',
  'submitted',
  'under_review',
  'answered',
  'closed',
  'cancelled'
);

create type public.rfi_priority as enum ('low', 'medium', 'high', 'critical');
create type public.rfi_impact_type as enum (
  'none',
  'schedule',
  'cost',
  'schedule_and_cost',
  'quality',
  'other'
);

create table public.rfis (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  rfi_number text not null,
  subject text not null,
  question text not null,
  drawing_references text,
  specification_references text,
  location text,
  raised_by uuid not null references public.profiles (id),
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  priority public.rfi_priority not null default 'medium',
  impact_type public.rfi_impact_type not null default 'none',
  potential_schedule_impact boolean not null default false,
  potential_cost_impact boolean not null default false,
  date_raised date not null default (timezone('utc', now()))::date,
  response_required_by timestamptz,
  submitted_to text,
  status public.rfi_status not null default 'draft',
  response text,
  responded_by uuid references public.profiles (id) on delete set null,
  response_date timestamptz,
  related_stage_id uuid references public.project_stages (id) on delete set null,
  related_document_id uuid references public.documents (id) on delete set null,
  related_ncr_id uuid,
  closed_at timestamptz,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, rfi_number)
);

create trigger rfis_set_updated_at
  before update on public.rfis
  for each row execute function public.set_updated_at();

create index rfis_project_idx on public.rfis (project_id, status);
create index rfis_due_idx on public.rfis (response_required_by, status);
create index rfis_discipline_idx on public.rfis (discipline_id);
create index rfis_responsible_idx on public.rfis (responsible_engineer_id);

-- Prevent silent mutation of closed RFIs (question/response integrity)
create or replace function public.protect_closed_rfi()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('closed', 'cancelled') and new.status = old.status then
    if old.question is distinct from new.question
       or old.subject is distinct from new.subject
       or (old.response is not null and old.response is distinct from new.response) then
      raise exception 'CONFLICT';
    end if;
  end if;
  return new;
end;
$$;

create trigger rfis_protect_closed
  before update on public.rfis
  for each row execute function public.protect_closed_rfi();


-- ===== 018_material_submittals.sql =====

-- Master Touch OS — 018
-- Material Submittals.

create type public.submittal_status as enum (
  'draft',
  'internal_review',
  'ready_for_submission',
  'submitted',
  'under_review',
  'approved',
  'approved_as_noted',
  'resubmit',
  'rejected',
  'for_information',
  'superseded',
  'closed'
);

create table public.material_submittals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  mat_number text not null,
  material_category text not null,
  manufacturer text,
  supplier text,
  model text,
  country_of_origin text,
  specification_section text,
  boq_reference text,
  proposed_use_location text,
  technical_description text,
  samples_required boolean not null default false,
  sample_status text,
  submitted_by uuid references public.profiles (id) on delete set null,
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  submission_date date,
  required_approval_date date,
  consultant_client text,
  status public.submittal_status not null default 'draft',
  official_decision text check (official_decision is null or official_decision in ('A', 'B', 'C', 'D', 'E')),
  review_comments text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, mat_number)
);

create trigger material_submittals_set_updated_at
  before update on public.material_submittals
  for each row execute function public.set_updated_at();

create index material_submittals_project_idx on public.material_submittals (project_id, status);
create index material_submittals_decision_idx on public.material_submittals (official_decision);
create index material_submittals_due_idx on public.material_submittals (required_approval_date, status);


-- ===== 019_shop_drawings.sql =====

-- Master Touch OS — 019
-- Shop Drawings.

create type public.shop_drawing_status as enum (
  'draft',
  'internal_review',
  'ready_for_submission',
  'submitted',
  'under_review',
  'approved',
  'approved_as_noted',
  'resubmit',
  'rejected',
  'superseded',
  'closed'
);

create table public.shop_drawings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  shd_number text not null,
  drawing_title text not null,
  drawing_number text,
  related_design_drawing text,
  floor_zone_location text,
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  prepared_by uuid references public.profiles (id) on delete set null,
  checked_by uuid references public.profiles (id) on delete set null,
  submission_date date,
  status public.shop_drawing_status not null default 'draft',
  official_decision text check (official_decision is null or official_decision in ('A', 'B', 'C', 'D', 'E')),
  approval_comments text,
  approved_for_execution boolean not null default false,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, shd_number)
);

create trigger shop_drawings_set_updated_at
  before update on public.shop_drawings
  for each row execute function public.set_updated_at();

create index shop_drawings_project_idx on public.shop_drawings (project_id, status);
create index shop_drawings_afe_idx on public.shop_drawings (project_id, approved_for_execution)
  where approved_for_execution = true;

-- Only A/B current revisions may be marked approved for execution
create or replace function public.enforce_shop_drawing_afe()
returns trigger
language plpgsql
as $$
begin
  if new.approved_for_execution = true then
    if new.official_decision is distinct from 'A' and new.official_decision is distinct from 'B' then
      raise exception 'VALIDATION';
    end if;
    if new.status in ('resubmit', 'rejected', 'superseded', 'draft') then
      raise exception 'VALIDATION';
    end if;
  end if;
  return new;
end;
$$;

create trigger shop_drawings_enforce_afe
  before insert or update on public.shop_drawings
  for each row execute function public.enforce_shop_drawing_afe();


-- ===== 020_method_statements.sql =====

-- Master Touch OS — 020
-- Method Statements.

create type public.method_statement_status as enum (
  'draft',
  'internal_review',
  'hse_review',
  'quality_review',
  'pm_review',
  'ready_for_submission',
  'submitted',
  'under_review',
  'approved',
  'approved_as_noted',
  'resubmit',
  'rejected',
  'approved_for_use',
  'superseded',
  'closed'
);

create table public.method_statements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  ms_number text not null,
  activity text not null,
  scope text,
  responsible_engineer_id uuid references public.profiles (id) on delete set null,
  method_procedure text,
  required_manpower text,
  equipment_tools text,
  materials text,
  safety_requirements text,
  quality_requirements text,
  inspection_testing_requirements text,
  references_text text,
  requires_hse_review boolean not null default true,
  requires_quality_review boolean not null default true,
  status public.method_statement_status not null default 'draft',
  official_decision text check (official_decision is null or official_decision in ('A', 'B', 'C', 'D', 'E')),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, ms_number)
);

create trigger method_statements_set_updated_at
  before update on public.method_statements
  for each row execute function public.set_updated_at();

create index method_statements_project_idx on public.method_statements (project_id, status);


-- ===== 021_inspection_requests.sql =====

-- Master Touch OS — 021
-- Inspection Requests.

create type public.inspection_status as enum (
  'draft',
  'ready',
  'submitted',
  'scheduled',
  'inspected',
  'passed',
  'passed_with_comments',
  'failed',
  'reinspection_required',
  'closed'
);

create table public.inspection_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  ir_number text not null,
  related_activity text,
  location text,
  related_drawing_id uuid references public.documents (id) on delete set null,
  related_method_statement_id uuid references public.method_statements (id) on delete set null,
  related_material_submittal_id uuid references public.material_submittals (id) on delete set null,
  inspection_date_requested date,
  requested_by uuid references public.profiles (id) on delete set null,
  site_engineer_id uuid references public.profiles (id) on delete set null,
  quality_engineer_id uuid references public.profiles (id) on delete set null,
  consultant_inspector text,
  checklist jsonb not null default '[]'::jsonb,
  inspection_result text,
  comments text,
  status public.inspection_status not null default 'draft',
  parent_inspection_id uuid references public.inspection_requests (id) on delete set null,
  related_ncr_id uuid,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, ir_number)
);

create trigger inspection_requests_set_updated_at
  before update on public.inspection_requests
  for each row execute function public.set_updated_at();

create index inspection_requests_project_idx on public.inspection_requests (project_id, status);
create index inspection_requests_parent_idx on public.inspection_requests (parent_inspection_id);


-- ===== 022_ncr.sql =====

-- Master Touch OS — 022
-- NCR (Non-Conformance Reports).

create type public.ncr_severity as enum ('low', 'medium', 'high', 'critical');

create type public.ncr_status as enum (
  'open',
  'under_investigation',
  'corrective_action',
  'waiting_verification',
  'closed',
  'reopened'
);

create table public.ncrs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid not null unique references public.documents (id) on delete restrict,
  discipline_id uuid references public.engineering_disciplines (id) on delete set null,
  ncr_number text not null,
  location text,
  reported_by uuid not null references public.profiles (id),
  assigned_to uuid references public.profiles (id) on delete set null,
  severity public.ncr_severity not null default 'medium',
  description text not null,
  requirement_violated text,
  evidence_notes text,
  root_cause text,
  corrective_action text,
  preventive_action text,
  responsible_person_id uuid references public.profiles (id) on delete set null,
  target_closure_date date,
  actual_closure_date date,
  verification text,
  verified_by uuid references public.profiles (id) on delete set null,
  verified_at timestamptz,
  status public.ncr_status not null default 'open',
  related_inspection_id uuid references public.inspection_requests (id) on delete set null,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, ncr_number),
  check (
    status <> 'closed'
    or (verification is not null and verified_by is not null)
  )
);

create trigger ncrs_set_updated_at
  before update on public.ncrs
  for each row execute function public.set_updated_at();

create index ncrs_project_idx on public.ncrs (project_id, status);
create index ncrs_severity_idx on public.ncrs (severity, status);
create index ncrs_due_idx on public.ncrs (target_closure_date, status);

-- Backfill FKs from RFI / IR that reference NCR
alter table public.rfis
  add constraint rfis_related_ncr_fk
  foreign key (related_ncr_id) references public.ncrs (id) on delete set null;

alter table public.inspection_requests
  add constraint inspection_requests_related_ncr_fk
  foreign key (related_ncr_id) references public.ncrs (id) on delete set null;


-- ===== 023_reports_correspondence.sql =====

-- Master Touch OS — 023
-- Project reports and formal correspondence register.

create type public.project_report_type as enum ('daily', 'weekly', 'monthly');

create type public.project_report_status as enum (
  'draft',
  'submitted',
  'approved',
  'archived'
);

create table public.project_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid references public.documents (id) on delete set null,
  report_type public.project_report_type not null,
  report_number text,
  period_start date not null,
  period_end date not null,
  prepared_by uuid not null references public.profiles (id),
  weather_site_condition text,
  manpower jsonb not null default '{}'::jsonb,
  activities_completed text,
  activities_in_progress text,
  planned_activities text,
  delays text,
  issues text,
  risks text,
  materials_received text,
  inspections_summary text,
  safety_observations text,
  notes text,
  management_summary text,
  status public.project_report_status not null default 'draft',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (period_end >= period_start)
);

create trigger project_reports_set_updated_at
  before update on public.project_reports
  for each row execute function public.set_updated_at();

create index project_reports_project_idx on public.project_reports (project_id, report_type, period_start desc);

create type public.correspondence_direction as enum ('incoming', 'outgoing', 'internal');

create type public.correspondence_status as enum (
  'open',
  'awaiting_response',
  'responded',
  'closed'
);

create table public.correspondence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  document_id uuid references public.documents (id) on delete set null,
  reference_number text not null,
  direction public.correspondence_direction not null,
  sender text not null,
  recipient text not null,
  cc text,
  subject text not null,
  body_summary text,
  correspondence_date date not null default (timezone('utc', now()))::date,
  response_required boolean not null default false,
  response_due_date date,
  response_received boolean not null default false,
  related_entity_type text,
  related_entity_id uuid,
  status public.correspondence_status not null default 'open',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, reference_number)
);

create trigger correspondence_set_updated_at
  before update on public.correspondence
  for each row execute function public.set_updated_at();

create index correspondence_project_idx on public.correspondence (project_id, status);
create index correspondence_due_idx on public.correspondence (response_due_date, status)
  where response_required = true;


-- ===== 024_contacts_transmittals.sql =====

-- Master Touch OS — 024
-- Project contacts and formal transmittals.

create type public.project_contact_type as enum (
  'client',
  'consultant',
  'supplier',
  'subcontractor',
  'other'
);

create table public.project_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  company_name text not null,
  contact_name text not null,
  role_title text,
  email text,
  phone text,
  whatsapp_phone text,
  contact_type public.project_contact_type not null default 'other',
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger project_contacts_set_updated_at
  before update on public.project_contacts
  for each row execute function public.set_updated_at();

create index project_contacts_project_idx on public.project_contacts (project_id, contact_type, is_active);

create type public.transmittal_direction as enum ('outgoing', 'incoming');

create type public.transmittal_status as enum (
  'draft',
  'issued',
  'acknowledged',
  'closed',
  'cancelled'
);

create type public.transmittal_purpose as enum (
  'for_approval',
  'for_review',
  'for_information',
  'for_construction',
  'for_record'
);

create table public.transmittals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  transmittal_number text not null,
  direction public.transmittal_direction not null default 'outgoing',
  recipient text not null,
  subject text not null,
  description text,
  issued_by uuid references public.profiles (id) on delete set null,
  issued_date date,
  issued_at timestamptz,
  response_required boolean not null default false,
  response_due date,
  status public.transmittal_status not null default 'draft',
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, transmittal_number)
);

create trigger transmittals_set_updated_at
  before update on public.transmittals
  for each row execute function public.set_updated_at();

create index transmittals_project_idx on public.transmittals (project_id, status);

create table public.transmittal_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  transmittal_id uuid not null references public.transmittals (id) on delete cascade,
  document_id uuid not null references public.documents (id) on delete restrict,
  document_version_id uuid not null references public.document_versions (id) on delete restrict,
  purpose public.transmittal_purpose not null default 'for_review',
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (transmittal_id, document_version_id)
);

create index transmittal_items_transmittal_idx on public.transmittal_items (transmittal_id);

-- Issued transmittals and their items are immutable
create or replace function public.protect_issued_transmittal()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'transmittals' then
    if old.status = 'issued' and old.issued_at is not null then
      if new.recipient is distinct from old.recipient
         or new.subject is distinct from old.subject
         or new.description is distinct from old.description
         or new.issued_date is distinct from old.issued_date then
        raise exception 'CONFLICT';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger transmittals_protect_issued
  before update on public.transmittals
  for each row execute function public.protect_issued_transmittal();

create or replace function public.protect_issued_transmittal_items()
returns trigger
language plpgsql
as $$
declare
  v_status public.transmittal_status;
begin
  select status into v_status from public.transmittals where id = coalesce(new.transmittal_id, old.transmittal_id);
  if v_status = 'issued' then
    raise exception 'CONFLICT';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger transmittal_items_protect_issued
  before insert or update or delete on public.transmittal_items
  for each row execute function public.protect_issued_transmittal_items();


-- ===== 025_phase2_rbac.sql =====

-- Master Touch OS — 025
-- Phase 2 RBAC permissions, role mappings, and project.read_all for org-wide access.

insert into public.permissions (key, resource, action, description_ar, description_en) values
  ('project.read_all', 'project', 'read_all', 'عرض جميع مشاريع المنشأة', 'Read all organization projects'),
  ('engineering.read', 'engineering', 'read', 'عرض الهندسة', 'Read engineering'),
  ('engineering.manage', 'engineering', 'manage', 'إدارة الهندسة', 'Manage engineering'),
  ('document_control.read', 'document_control', 'read', 'عرض مراقبة الوثائق', 'Read document control'),
  ('document_control.register', 'document_control', 'register', 'تسجيل وثيقة', 'Register document'),
  ('document_control.submit', 'document_control', 'submit', 'إصدار وثيقة', 'Submit document'),
  ('document_control.revise', 'document_control', 'revise', 'إنشاء مراجعة', 'Revise document'),
  ('rfi.create', 'rfi', 'create', 'إنشاء طلب استفسار', 'Create RFI'),
  ('rfi.read', 'rfi', 'read', 'عرض طلبات الاستفسار', 'Read RFI'),
  ('rfi.update', 'rfi', 'update', 'تحديث طلب استفسار', 'Update RFI'),
  ('rfi.submit', 'rfi', 'submit', 'تقديم طلب استفسار', 'Submit RFI'),
  ('rfi.respond', 'rfi', 'respond', 'الرد على طلب استفسار', 'Respond to RFI'),
  ('rfi.close', 'rfi', 'close', 'إغلاق طلب استفسار', 'Close RFI'),
  ('submittal.create', 'submittal', 'create', 'إنشاء اعتماد مواد', 'Create material submittal'),
  ('submittal.read', 'submittal', 'read', 'عرض اعتماد المواد', 'Read material submittal'),
  ('submittal.update', 'submittal', 'update', 'تحديث اعتماد مواد', 'Update material submittal'),
  ('submittal.submit', 'submittal', 'submit', 'تقديم اعتماد مواد', 'Submit material submittal'),
  ('shop_drawing.create', 'shop_drawing', 'create', 'إنشاء مخطط تنفيذي', 'Create shop drawing'),
  ('shop_drawing.read', 'shop_drawing', 'read', 'عرض المخططات التنفيذية', 'Read shop drawing'),
  ('shop_drawing.update', 'shop_drawing', 'update', 'تحديث مخطط تنفيذي', 'Update shop drawing'),
  ('shop_drawing.submit', 'shop_drawing', 'submit', 'تقديم مخطط تنفيذي', 'Submit shop drawing'),
  ('method_statement.create', 'method_statement', 'create', 'إنشاء طريقة تنفيذ', 'Create method statement'),
  ('method_statement.read', 'method_statement', 'read', 'عرض طرق التنفيذ', 'Read method statement'),
  ('method_statement.update', 'method_statement', 'update', 'تحديث طريقة تنفيذ', 'Update method statement'),
  ('method_statement.submit', 'method_statement', 'submit', 'تقديم طريقة تنفيذ', 'Submit method statement'),
  ('inspection.create', 'inspection', 'create', 'إنشاء طلب فحص', 'Create inspection request'),
  ('inspection.read', 'inspection', 'read', 'عرض طلبات الفحص', 'Read inspection'),
  ('inspection.perform', 'inspection', 'perform', 'تنفيذ فحص', 'Perform inspection'),
  ('inspection.close', 'inspection', 'close', 'إغلاق طلب فحص', 'Close inspection'),
  ('ncr.create', 'ncr', 'create', 'إنشاء تقرير عدم مطابقة', 'Create NCR'),
  ('ncr.read', 'ncr', 'read', 'عرض تقارير عدم المطابقة', 'Read NCR'),
  ('ncr.manage', 'ncr', 'manage', 'إدارة تقرير عدم مطابقة', 'Manage NCR'),
  ('ncr.close', 'ncr', 'close', 'إغلاق تقرير عدم مطابقة', 'Close NCR'),
  ('report.create', 'report', 'create', 'إنشاء تقرير مشروع', 'Create project report'),
  ('report.read', 'report', 'read', 'عرض تقارير المشروع', 'Read project report'),
  ('report.approve', 'report', 'approve', 'اعتماد تقرير مشروع', 'Approve project report'),
  ('correspondence.create', 'correspondence', 'create', 'إنشاء مراسلة', 'Create correspondence'),
  ('correspondence.read', 'correspondence', 'read', 'عرض المراسلات', 'Read correspondence'),
  ('correspondence.manage', 'correspondence', 'manage', 'إدارة المراسلات', 'Manage correspondence'),
  ('transmittal.create', 'transmittal', 'create', 'إنشاء إرسالية', 'Create transmittal'),
  ('transmittal.read', 'transmittal', 'read', 'عرض الإرساليات', 'Read transmittal'),
  ('transmittal.issue', 'transmittal', 'issue', 'إصدار إرسالية', 'Issue transmittal')
on conflict (key) do nothing;

-- Org-wide project visibility
insert into public.role_permissions (role_id, permission_key)
select r.id, 'project.read_all'
from public.roles r
where r.code in (
  'super_admin', 'general_manager', 'operations_manager',
  'document_controller', 'quality_manager', 'finance_manager'
)
on conflict do nothing;

-- Engineering / DC / module permissions by role
insert into public.role_permissions (role_id, permission_key)
select r.id, p.key
from public.roles r
cross join public.permissions p
where r.code = 'super_admin'
  and p.key in (
    select key from public.permissions
    where key like 'engineering.%'
       or key like 'document_control.%'
       or key like 'rfi.%'
       or key like 'submittal.%'
       or key like 'shop_drawing.%'
       or key like 'method_statement.%'
       or key like 'inspection.%'
       or key like 'ncr.%'
       or key like 'report.%'
       or key like 'correspondence.%'
       or key like 'transmittal.%'
       or key = 'project.read_all'
  )
on conflict do nothing;

insert into public.role_permissions (role_id, permission_key)
select r.id, x.permission_key
from public.roles r
join (values
  ('general_manager', 'project.read_all'),
  ('general_manager', 'engineering.read'),
  ('general_manager', 'engineering.manage'),
  ('general_manager', 'document_control.read'),
  ('general_manager', 'rfi.read'),
  ('general_manager', 'submittal.read'),
  ('general_manager', 'shop_drawing.read'),
  ('general_manager', 'method_statement.read'),
  ('general_manager', 'inspection.read'),
  ('general_manager', 'ncr.read'),
  ('general_manager', 'ncr.manage'),
  ('general_manager', 'report.read'),
  ('general_manager', 'correspondence.read'),
  ('general_manager', 'transmittal.read'),
  ('operations_manager', 'project.read_all'),
  ('operations_manager', 'engineering.read'),
  ('operations_manager', 'engineering.manage'),
  ('operations_manager', 'document_control.read'),
  ('operations_manager', 'document_control.submit'),
  ('operations_manager', 'rfi.create'),
  ('operations_manager', 'rfi.read'),
  ('operations_manager', 'rfi.update'),
  ('operations_manager', 'rfi.submit'),
  ('operations_manager', 'rfi.close'),
  ('operations_manager', 'submittal.create'),
  ('operations_manager', 'submittal.read'),
  ('operations_manager', 'submittal.submit'),
  ('operations_manager', 'shop_drawing.create'),
  ('operations_manager', 'shop_drawing.read'),
  ('operations_manager', 'shop_drawing.submit'),
  ('operations_manager', 'method_statement.create'),
  ('operations_manager', 'method_statement.read'),
  ('operations_manager', 'method_statement.submit'),
  ('operations_manager', 'inspection.create'),
  ('operations_manager', 'inspection.read'),
  ('operations_manager', 'inspection.perform'),
  ('operations_manager', 'ncr.create'),
  ('operations_manager', 'ncr.read'),
  ('operations_manager', 'ncr.manage'),
  ('operations_manager', 'report.create'),
  ('operations_manager', 'report.read'),
  ('operations_manager', 'correspondence.create'),
  ('operations_manager', 'correspondence.read'),
  ('operations_manager', 'transmittal.create'),
  ('operations_manager', 'transmittal.read'),
  ('operations_manager', 'transmittal.issue'),
  ('project_manager', 'engineering.read'),
  ('project_manager', 'engineering.manage'),
  ('project_manager', 'document_control.read'),
  ('project_manager', 'document_control.register'),
  ('project_manager', 'document_control.submit'),
  ('project_manager', 'document_control.revise'),
  ('project_manager', 'document.approve'),
  ('project_manager', 'rfi.create'),
  ('project_manager', 'rfi.read'),
  ('project_manager', 'rfi.update'),
  ('project_manager', 'rfi.submit'),
  ('project_manager', 'rfi.respond'),
  ('project_manager', 'rfi.close'),
  ('project_manager', 'submittal.create'),
  ('project_manager', 'submittal.read'),
  ('project_manager', 'submittal.update'),
  ('project_manager', 'submittal.submit'),
  ('project_manager', 'shop_drawing.create'),
  ('project_manager', 'shop_drawing.read'),
  ('project_manager', 'shop_drawing.update'),
  ('project_manager', 'shop_drawing.submit'),
  ('project_manager', 'method_statement.create'),
  ('project_manager', 'method_statement.read'),
  ('project_manager', 'method_statement.update'),
  ('project_manager', 'method_statement.submit'),
  ('project_manager', 'inspection.create'),
  ('project_manager', 'inspection.read'),
  ('project_manager', 'inspection.perform'),
  ('project_manager', 'inspection.close'),
  ('project_manager', 'ncr.create'),
  ('project_manager', 'ncr.read'),
  ('project_manager', 'ncr.manage'),
  ('project_manager', 'ncr.close'),
  ('project_manager', 'report.create'),
  ('project_manager', 'report.read'),
  ('project_manager', 'report.approve'),
  ('project_manager', 'correspondence.create'),
  ('project_manager', 'correspondence.read'),
  ('project_manager', 'correspondence.manage'),
  ('project_manager', 'transmittal.create'),
  ('project_manager', 'transmittal.read'),
  ('project_manager', 'transmittal.issue'),
  ('project_engineer', 'engineering.read'),
  ('project_engineer', 'document_control.read'),
  ('project_engineer', 'rfi.create'),
  ('project_engineer', 'rfi.read'),
  ('project_engineer', 'rfi.update'),
  ('project_engineer', 'rfi.submit'),
  ('project_engineer', 'submittal.create'),
  ('project_engineer', 'submittal.read'),
  ('project_engineer', 'submittal.update'),
  ('project_engineer', 'submittal.submit'),
  ('project_engineer', 'shop_drawing.create'),
  ('project_engineer', 'shop_drawing.read'),
  ('project_engineer', 'shop_drawing.update'),
  ('project_engineer', 'shop_drawing.submit'),
  ('project_engineer', 'method_statement.create'),
  ('project_engineer', 'method_statement.read'),
  ('project_engineer', 'method_statement.update'),
  ('project_engineer', 'inspection.create'),
  ('project_engineer', 'inspection.read'),
  ('project_engineer', 'inspection.perform'),
  ('project_engineer', 'ncr.create'),
  ('project_engineer', 'ncr.read'),
  ('project_engineer', 'report.create'),
  ('project_engineer', 'report.read'),
  ('project_engineer', 'correspondence.read'),
  ('engineer', 'engineering.read'),
  ('engineer', 'rfi.create'),
  ('engineer', 'rfi.read'),
  ('engineer', 'rfi.update'),
  ('engineer', 'submittal.create'),
  ('engineer', 'submittal.read'),
  ('engineer', 'submittal.update'),
  ('engineer', 'shop_drawing.create'),
  ('engineer', 'shop_drawing.read'),
  ('engineer', 'shop_drawing.update'),
  ('engineer', 'method_statement.create'),
  ('engineer', 'method_statement.read'),
  ('engineer', 'inspection.create'),
  ('engineer', 'inspection.read'),
  ('engineer', 'ncr.create'),
  ('engineer', 'ncr.read'),
  ('engineer', 'report.create'),
  ('engineer', 'report.read'),
  ('document_controller', 'project.read_all'),
  ('document_controller', 'engineering.read'),
  ('document_controller', 'document_control.read'),
  ('document_controller', 'document_control.register'),
  ('document_controller', 'document_control.submit'),
  ('document_controller', 'document_control.revise'),
  ('document_controller', 'rfi.read'),
  ('document_controller', 'rfi.submit'),
  ('document_controller', 'submittal.read'),
  ('document_controller', 'submittal.submit'),
  ('document_controller', 'shop_drawing.read'),
  ('document_controller', 'shop_drawing.submit'),
  ('document_controller', 'method_statement.read'),
  ('document_controller', 'method_statement.submit'),
  ('document_controller', 'inspection.read'),
  ('document_controller', 'ncr.read'),
  ('document_controller', 'report.read'),
  ('document_controller', 'correspondence.create'),
  ('document_controller', 'correspondence.read'),
  ('document_controller', 'correspondence.manage'),
  ('document_controller', 'transmittal.create'),
  ('document_controller', 'transmittal.read'),
  ('document_controller', 'transmittal.issue'),
  ('quality_manager', 'project.read_all'),
  ('quality_manager', 'engineering.read'),
  ('quality_manager', 'inspection.create'),
  ('quality_manager', 'inspection.read'),
  ('quality_manager', 'inspection.perform'),
  ('quality_manager', 'inspection.close'),
  ('quality_manager', 'ncr.create'),
  ('quality_manager', 'ncr.read'),
  ('quality_manager', 'ncr.manage'),
  ('quality_manager', 'ncr.close'),
  ('quality_manager', 'method_statement.read'),
  ('quality_officer', 'engineering.read'),
  ('quality_officer', 'inspection.create'),
  ('quality_officer', 'inspection.read'),
  ('quality_officer', 'inspection.perform'),
  ('quality_officer', 'ncr.create'),
  ('quality_officer', 'ncr.read'),
  ('hse_manager', 'engineering.read'),
  ('hse_manager', 'method_statement.read'),
  ('hse_manager', 'inspection.read'),
  ('hse_manager', 'ncr.read'),
  ('hse_officer', 'method_statement.read'),
  ('hse_officer', 'inspection.read')
) as x(code, permission_key) on x.code = r.code
on conflict do nothing;


-- ===== 026_phase2_rls.sql =====

-- Master Touch OS — 026
-- Phase 2 RLS + tightened project-scoped access (project.read_all).

-- Tighten can_access_project: org-scoped project.read alone is insufficient.
create or replace function public.can_access_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.projects pr
    where pr.id = p_project_id
      and (
        public.is_platform_admin()
        or (
          public.is_organization_member(pr.organization_id)
          and (
            public.has_permission('project.read_all', pr.organization_id, 'organization', null)
            or public.has_permission('project.read', pr.organization_id, 'project', pr.id)
            or pr.project_manager_id = auth.uid()
            or exists (
              select 1
              from public.project_members pm
              where pm.project_id = pr.id
                and pm.profile_id = auth.uid()
                and pm.is_active = true
            )
          )
        )
      )
  );
$$;

-- Helper: project-scoped module permission
create or replace function public.has_project_permission(
  p_permission_key text,
  p_project_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.projects pr
    where pr.id = p_project_id
      and (
        public.is_platform_admin()
        or (
          public.can_access_project(p_project_id)
          and (
            public.has_permission(p_permission_key, pr.organization_id, 'organization', null)
            or public.has_permission(p_permission_key, pr.organization_id, 'project', pr.id)
          )
        )
      )
  );
$$;

grant execute on function public.has_project_permission(text, uuid) to authenticated;

-- Enable RLS on Phase 2 tables
alter table public.engineering_disciplines enable row level security;
alter table public.project_disciplines enable row level security;
alter table public.document_type_codes enable row level security;
alter table public.document_number_counters enable row level security;
alter table public.rfis enable row level security;
alter table public.material_submittals enable row level security;
alter table public.shop_drawings enable row level security;
alter table public.method_statements enable row level security;
alter table public.inspection_requests enable row level security;
alter table public.ncrs enable row level security;
alter table public.project_reports enable row level security;
alter table public.correspondence enable row level security;
alter table public.project_contacts enable row level security;
alter table public.transmittals enable row level security;
alter table public.transmittal_items enable row level security;

drop policy if exists engineering_disciplines_select on public.engineering_disciplines;
create policy engineering_disciplines_select on public.engineering_disciplines
  for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists engineering_disciplines_write on public.engineering_disciplines;
create policy engineering_disciplines_write on public.engineering_disciplines
  for all to authenticated
  using (public.has_permission('engineering.manage', organization_id))
  with check (public.has_permission('engineering.manage', organization_id));

drop policy if exists project_disciplines_select on public.project_disciplines;
create policy project_disciplines_select on public.project_disciplines
  for select to authenticated
  using (public.can_access_project(project_id));

drop policy if exists project_disciplines_write on public.project_disciplines;
create policy project_disciplines_write on public.project_disciplines
  for all to authenticated
  using (public.has_project_permission('engineering.manage', project_id)
    or public.has_project_permission('project.update', project_id))
  with check (public.has_project_permission('engineering.manage', project_id)
    or public.has_project_permission('project.update', project_id));

drop policy if exists document_type_codes_select on public.document_type_codes;
create policy document_type_codes_select on public.document_type_codes
  for select to authenticated
  using (public.is_active_profile());

drop policy if exists document_number_counters_all on public.document_number_counters;
create policy document_number_counters_all on public.document_number_counters
  for all to authenticated
  using (public.has_permission('document_control.register', organization_id)
    or public.has_permission('document.upload', organization_id))
  with check (public.has_permission('document_control.register', organization_id)
    or public.has_permission('document.upload', organization_id));

-- Generic project-scoped policies for operational modules
drop policy if exists rfis_select on public.rfis;
create policy rfis_select on public.rfis
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('rfi.read', project_id));

drop policy if exists rfis_insert on public.rfis;
create policy rfis_insert on public.rfis
  for insert to authenticated
  with check (public.has_project_permission('rfi.create', project_id));

drop policy if exists rfis_update on public.rfis;
create policy rfis_update on public.rfis
  for update to authenticated
  using (
    public.has_project_permission('rfi.update', project_id)
    or public.has_project_permission('rfi.respond', project_id)
    or public.has_project_permission('rfi.close', project_id)
    or public.has_project_permission('rfi.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists material_submittals_select on public.material_submittals;
create policy material_submittals_select on public.material_submittals
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('submittal.read', project_id));

drop policy if exists material_submittals_insert on public.material_submittals;
create policy material_submittals_insert on public.material_submittals
  for insert to authenticated
  with check (public.has_project_permission('submittal.create', project_id));

drop policy if exists material_submittals_update on public.material_submittals;
create policy material_submittals_update on public.material_submittals
  for update to authenticated
  using (
    public.has_project_permission('submittal.update', project_id)
    or public.has_project_permission('submittal.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists shop_drawings_select on public.shop_drawings;
create policy shop_drawings_select on public.shop_drawings
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('shop_drawing.read', project_id));

drop policy if exists shop_drawings_insert on public.shop_drawings;
create policy shop_drawings_insert on public.shop_drawings
  for insert to authenticated
  with check (public.has_project_permission('shop_drawing.create', project_id));

drop policy if exists shop_drawings_update on public.shop_drawings;
create policy shop_drawings_update on public.shop_drawings
  for update to authenticated
  using (
    public.has_project_permission('shop_drawing.update', project_id)
    or public.has_project_permission('shop_drawing.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists method_statements_select on public.method_statements;
create policy method_statements_select on public.method_statements
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('method_statement.read', project_id));

drop policy if exists method_statements_insert on public.method_statements;
create policy method_statements_insert on public.method_statements
  for insert to authenticated
  with check (public.has_project_permission('method_statement.create', project_id));

drop policy if exists method_statements_update on public.method_statements;
create policy method_statements_update on public.method_statements
  for update to authenticated
  using (
    public.has_project_permission('method_statement.update', project_id)
    or public.has_project_permission('method_statement.submit', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists inspection_requests_select on public.inspection_requests;
create policy inspection_requests_select on public.inspection_requests
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('inspection.read', project_id));

drop policy if exists inspection_requests_insert on public.inspection_requests;
create policy inspection_requests_insert on public.inspection_requests
  for insert to authenticated
  with check (public.has_project_permission('inspection.create', project_id));

drop policy if exists inspection_requests_update on public.inspection_requests;
create policy inspection_requests_update on public.inspection_requests
  for update to authenticated
  using (
    public.has_project_permission('inspection.perform', project_id)
    or public.has_project_permission('inspection.close', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists ncrs_select on public.ncrs;
create policy ncrs_select on public.ncrs
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('ncr.read', project_id));

drop policy if exists ncrs_insert on public.ncrs;
create policy ncrs_insert on public.ncrs
  for insert to authenticated
  with check (public.has_project_permission('ncr.create', project_id));

drop policy if exists ncrs_update on public.ncrs;
create policy ncrs_update on public.ncrs
  for update to authenticated
  using (
    public.has_project_permission('ncr.manage', project_id)
    or public.has_project_permission('ncr.close', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists project_reports_select on public.project_reports;
create policy project_reports_select on public.project_reports
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('report.read', project_id));

drop policy if exists project_reports_insert on public.project_reports;
create policy project_reports_insert on public.project_reports
  for insert to authenticated
  with check (public.has_project_permission('report.create', project_id));

drop policy if exists project_reports_update on public.project_reports;
create policy project_reports_update on public.project_reports
  for update to authenticated
  using (
    public.has_project_permission('report.create', project_id)
    or public.has_project_permission('report.approve', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists correspondence_select on public.correspondence;
create policy correspondence_select on public.correspondence
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('correspondence.read', project_id));

drop policy if exists correspondence_insert on public.correspondence;
create policy correspondence_insert on public.correspondence
  for insert to authenticated
  with check (public.has_project_permission('correspondence.create', project_id));

drop policy if exists correspondence_update on public.correspondence;
create policy correspondence_update on public.correspondence
  for update to authenticated
  using (public.has_project_permission('correspondence.manage', project_id))
  with check (public.can_access_project(project_id));

drop policy if exists project_contacts_select on public.project_contacts;
create policy project_contacts_select on public.project_contacts
  for select to authenticated
  using (public.can_access_project(project_id));

drop policy if exists project_contacts_write on public.project_contacts;
create policy project_contacts_write on public.project_contacts
  for all to authenticated
  using (public.has_project_permission('project.update', project_id)
    or public.has_project_permission('correspondence.manage', project_id))
  with check (public.has_project_permission('project.update', project_id)
    or public.has_project_permission('correspondence.manage', project_id));

drop policy if exists transmittals_select on public.transmittals;
create policy transmittals_select on public.transmittals
  for select to authenticated
  using (public.can_access_project(project_id) and public.has_project_permission('transmittal.read', project_id));

drop policy if exists transmittals_insert on public.transmittals;
create policy transmittals_insert on public.transmittals
  for insert to authenticated
  with check (public.has_project_permission('transmittal.create', project_id));

drop policy if exists transmittals_update on public.transmittals;
create policy transmittals_update on public.transmittals
  for update to authenticated
  using (
    public.has_project_permission('transmittal.create', project_id)
    or public.has_project_permission('transmittal.issue', project_id)
  )
  with check (public.can_access_project(project_id));

drop policy if exists transmittal_items_select on public.transmittal_items;
create policy transmittal_items_select on public.transmittal_items
  for select to authenticated
  using (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and public.can_access_project(t.project_id)
      and public.has_project_permission('transmittal.read', t.project_id)
  ));

drop policy if exists transmittal_items_write on public.transmittal_items;
create policy transmittal_items_write on public.transmittal_items
  for all to authenticated
  using (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and t.status = 'draft'
      and public.has_project_permission('transmittal.create', t.project_id)
  ))
  with check (exists (
    select 1 from public.transmittals t
    where t.id = transmittal_id
      and t.status = 'draft'
      and public.has_project_permission('transmittal.create', t.project_id)
  ));


-- ===== 027_phase2_rpc.sql =====

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


-- ===== 028_phase2_indexes_workflows.sql =====

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


-- ===== 029_document_version_lifecycle.sql =====

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

