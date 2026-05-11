-- Public Android APK metadata + private storage bucket for artifacts (served via signed URLs from the API).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'app-distributions',
  'app-distributions',
  false,
  157286400,
  array['application/vnd.android.package-archive', 'application/octet-stream']::text[]
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  version_label text not null,
  version_code int not null default 1,
  channel text not null default 'production',
  release_notes text not null default '',
  apk_storage_path text not null unique,
  apk_filename text not null,
  apk_byte_size bigint not null check (apk_byte_size > 0),
  apk_sha256_hex text not null,
  created_at timestamptz not null default now(),
  constraint app_releases_channel_chk check (channel in ('production', 'beta', 'internal'))
);

create index if not exists app_releases_channel_sort_idx
  on public.app_releases (channel, version_code desc, created_at desc);

comment on table public.app_releases is 'Android APK builds; binary lives in app-distributions bucket.';

alter table public.app_releases enable row level security;

drop policy if exists "app_releases_select_public" on public.app_releases;
create policy "app_releases_select_public"
  on public.app_releases for select
  to anon, authenticated
  using (true);

