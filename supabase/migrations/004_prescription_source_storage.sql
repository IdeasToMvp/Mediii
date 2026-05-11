-- Original uploaded files linked to prescriptions / reports

alter table public.prescriptions
  add column if not exists source_storage_path text,
  add column if not exists source_mime text,
  add column if not exists source_original_name text;

comment on column public.prescriptions.source_storage_path is 'Bucket path under prescription-sources: {user_id}/{uuid}.{ext}';

-- Private bucket per user-folder path (validated by policies)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('prescription-sources', 'prescription-sources', false, 10485760, null)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit;

drop policy if exists "prescription_sources_select_own" on storage.objects;
drop policy if exists "prescription_sources_insert_own" on storage.objects;
drop policy if exists "prescription_sources_delete_own" on storage.objects;

create policy "prescription_sources_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'prescription-sources'
    and split_part(name, '/', 1) = auth.uid()::text
  );

create policy "prescription_sources_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'prescription-sources'
    and split_part(name, '/', 1) = auth.uid()::text
  );

create policy "prescription_sources_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'prescription-sources'
    and split_part(name, '/', 1) = auth.uid()::text
  );
