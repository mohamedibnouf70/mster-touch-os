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
