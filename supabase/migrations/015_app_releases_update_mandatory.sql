-- Whether clients should force-install this build (blocking prompt).

alter table public.app_releases
  add column if not exists update_mandatory boolean not null default false;

comment on column public.app_releases.update_mandatory is
  'When true, clients should treat the update as required (non-dismissible prompt). Publish time stays in created_at.';
