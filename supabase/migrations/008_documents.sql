-- Master Touch OS — 008
-- Document control foundation. Revisions are append-only.

create table public.document_categories (
  code text primary key,
  name_ar text not null,
  name_en text not null
);

insert into public.document_categories (code, name_ar, name_en) values
  ('business_case', 'دراسة الجدوى', 'Business Case'),
  ('contract', 'عقد', 'Contract'),
  ('drawing', 'مخطط', 'Drawing'),
  ('shop_drawing', 'مخطط ورشة', 'Shop Drawing'),
  ('material_submittal', 'اعتماد مواد', 'Material Submittal'),
  ('rfi', 'طلب استيضاح', 'RFI'),
  ('method_statement', 'بيان طريقة التنفيذ', 'Method Statement'),
  ('inspection_request', 'طلب فحص', 'Inspection Request'),
  ('ncr', 'تقرير عدم مطابقة', 'NCR'),
  ('invoice', 'فاتورة', 'Invoice'),
  ('purchase_order', 'أمر شراء', 'Purchase Order'),
  ('change_order', 'أمر تغيير', 'Change Order'),
  ('handover', 'تسليم', 'Handover'),
  ('warranty', 'ضمان', 'Warranty'),
  ('other', 'أخرى', 'Other');

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  project_id uuid references public.projects (id) on delete set null,
  category text not null references public.document_categories (code),
  document_number text,
  title text not null,
  current_revision text not null default 'A',
  status public.document_status not null default 'draft',
  discipline text,
  confidentiality public.confidentiality_level not null default 'internal',
  approval_state text not null default 'pending',
  uploaded_by uuid not null references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger documents_set_updated_at
  before update on public.documents
  for each row execute function public.set_updated_at();

create index documents_org_idx on public.documents (organization_id, created_at desc);
create index documents_project_idx on public.documents (project_id);
create index documents_category_idx on public.documents (category);

alter table public.projects
  add constraint projects_business_case_document_fk
  foreign key (business_case_document_id) references public.documents (id) on delete set null;

create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  document_id uuid not null references public.documents (id) on delete cascade,
  revision text not null,
  file_path text not null,
  file_name text not null,
  mime_type text not null,
  size_bytes bigint not null,
  checksum text,
  uploaded_by uuid not null references public.profiles (id),
  uploaded_at timestamptz not null default timezone('utc', now()),
  unique (document_id, revision)
);

create index document_versions_document_idx on public.document_versions (document_id, uploaded_at desc);
