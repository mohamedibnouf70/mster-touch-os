-- Master Touch OS — 012
-- Private document bucket and storage policies.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documents',
  'documents',
  false,
  52428800,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/msword',
    'application/vnd.ms-excel',
    'text/plain',
    'application/acad',
    'image/vnd.dwg',
    'application/dxf'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy documents_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents'
    and public.is_organization_member((storage.foldername(name))[1]::uuid)
    and public.has_permission('document.read', (storage.foldername(name))[1]::uuid)
  );

create policy documents_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documents'
    and public.has_permission('document.upload', (storage.foldername(name))[1]::uuid)
  );

create policy documents_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'documents'
    and public.has_permission('document.update', (storage.foldername(name))[1]::uuid)
  )
  with check (
    bucket_id = 'documents'
    and public.has_permission('document.update', (storage.foldername(name))[1]::uuid)
  );
