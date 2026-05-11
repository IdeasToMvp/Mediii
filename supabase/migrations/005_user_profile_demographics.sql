-- Optional demographics for the account profile (name remains display_name).

alter table public.user_profiles
  add column if not exists birth_year smallint,
  add column if not exists gender text;

comment on column public.user_profiles.birth_year is 'Approximate age derived in app from birth year';
comment on column public.user_profiles.gender is 'One of female|male|non_binary|prefer_not_say|other or null';
