-- Platform discriminator for store-style releases (Android now; iOS ready for URLs / uploads later).

alter table public.app_releases
  add column if not exists platform text not null default 'android';

update public.app_releases set platform = 'android' where platform is null or platform = '';

alter table public.app_releases drop constraint if exists app_releases_platform_chk;
alter table public.app_releases
  add constraint app_releases_platform_chk check (platform in ('android', 'ios'));

drop index if exists app_releases_channel_sort_idx;

create index if not exists app_releases_channel_platform_sort_idx
  on public.app_releases (channel, platform, version_code desc, created_at desc);

comment on column public.app_releases.platform is 'android | ios — latest/release queries filter by this.';
