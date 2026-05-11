-- Raise APK bucket limit (large debug splits / bundled assets can exceed 150 MiB).
-- 500 MiB — if you need more, increase here and match backend APK_UPLOAD_MAX_BYTES.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'app-distributions',
  'app-distributions',
  false,
  524288000,
  array['application/vnd.android.package-archive', 'application/octet-stream']::text[]
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
