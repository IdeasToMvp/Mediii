-- Allow releases to point at an external APK URL (e.g. Google Drive) instead of Supabase Storage.

alter table public.app_releases
  add column if not exists apk_download_url text;

alter table public.app_releases alter column apk_storage_path drop not null;

alter table public.app_releases alter column apk_sha256_hex drop not null;

alter table public.app_releases alter column apk_byte_size drop not null;

alter table public.app_releases drop constraint if exists app_releases_download_xor_chk;

alter table public.app_releases
  add constraint app_releases_download_xor_chk check (
    (apk_download_url is null and apk_storage_path is not null)
    or (apk_download_url is not null and apk_storage_path is null)
  );

comment on column public.app_releases.apk_download_url is 'Hosted HTTPS APK link (preferred over storage when buckets are painful). XOR with apk_storage_path.';
