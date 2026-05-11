-- Dashboard: subscription metadata, profiles, family, medicine schedules, prescription vs report
-- Apply after 001_prescriptions.sql in Supabase SQL editor.

-- ---------------------------------------------------------------------------
-- Plans (readable by clients; edits happen via Stripe/webhooks later).
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_plans (
  slug text primary key,
  display_name text not null,
  max_family_members int not null,
  monthly_ai_extractions int not null,
  created_at timestamptz not null default now()
);

insert into public.subscription_plans (slug, display_name, max_family_members, monthly_ai_extractions)
values
  ('free', 'Free', 2, 5),
  ('plus', 'Plus', 8, 100),
  ('pro', 'Pro', 24, -1)
on conflict (slug) do nothing;

create table if not exists public.user_entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  plan_slug text not null default 'free' references public.subscription_plans (slug),
  ai_extractions_used int not null default 0,
  usage_period_started_at timestamptz not null default (date_trunc('month', timezone('utc', now()))),
  updated_at timestamptz not null default now()
);

create index if not exists user_entitlements_plan_slug_idx on public.user_entitlements (plan_slug);

alter table public.user_entitlements enable row level security;

create policy "user_entitlements_select_own"
  on public.user_entitlements for select
  using (auth.uid() = user_id);

-- Controlled updates via functions only (clients cannot elevate plan arbitrarily).
create policy "user_entitlements_no_direct_update"
  on public.user_entitlements for update
  using (false);

create policy "user_entitlements_no_direct_insert"
  on public.user_entitlements for insert
  with check (false);

-- ---------------------------------------------------------------------------
create or replace function public.ensure_user_entitlements()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_entitlements (user_id)
  values (auth.uid())
  on conflict (user_id) do nothing;
end;
$$;

grant execute on function public.ensure_user_entitlements() to authenticated;

create or replace function public.increment_ai_extractions(amount int default 1)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caps int;
  used int := 0;
  plan_slug text;
  pid uuid := auth.uid();
begin
  if pid is null then
    return jsonb_build_object('allowed', false, 'reason', 'not_authenticated');
  end if;

  insert into public.user_entitlements (user_id)
  values (pid)
  on conflict (user_id) do nothing;

  -- Reset usage if UTC month rolled over.
  update public.user_entitlements ue
  set
    ai_extractions_used = 0,
    usage_period_started_at = date_trunc('month', timezone('utc', now())),
    updated_at = now()
  where ue.user_id = pid
    and ue.usage_period_started_at < date_trunc('month', timezone('utc', now()));

  select ue.plan_slug, ue.ai_extractions_used
  into plan_slug, used
  from public.user_entitlements ue
  where ue.user_id = pid;

  select sp.monthly_ai_extractions
  into caps
  from public.subscription_plans sp
  where sp.slug = plan_slug;

  -- -1 = unlimited
  if caps is distinct from null and caps >= 0 and (used + coalesce(amount, 1)) > caps then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'quota_exceeded',
      'used', used,
      'limit', caps,
      'plan_slug', plan_slug
    );
  end if;

  update public.user_entitlements ue
  set
    ai_extractions_used = ue.ai_extractions_used + greatest(coalesce(amount, 1), 1),
    updated_at = now()
  where ue.user_id = pid;

  select ue.ai_extractions_used into used
  from public.user_entitlements ue
  where ue.user_id = pid;

  return jsonb_build_object(
    'allowed', true,
    'used_after', coalesce(used, 0),
    'limit', caps,
    'plan_slug', plan_slug
  );
end;
$$;

grant execute on function public.increment_ai_extractions(int) to authenticated;

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  timezone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

create policy "profiles_select_own"
  on public.user_profiles for select
  using (auth.uid() = user_id);

create policy "profiles_insert_own"
  on public.user_profiles for insert
  with check (auth.uid() = user_id);

create policy "profiles_update_own"
  on public.user_profiles for update
  using (auth.uid() = user_id);

create policy "profiles_delete_own"
  on public.user_profiles for delete
  using (auth.uid() = user_id);

create table if not exists public.family_members (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null,
  relation text,
  birth_year smallint,
  notes text,
  avatar_color text default 'brand',
  sort_order smallint default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_display_nonempty check (char_length(trim(display_name)) > 0)
);

create index if not exists family_members_owner_idx on public.family_members (owner_user_id, sort_order, created_at);

alter table public.family_members enable row level security;

create policy "family_members_select_own"
  on public.family_members for select
  using (auth.uid() = owner_user_id);

create policy "family_members_insert_own"
  on public.family_members for insert
  with check (auth.uid() = owner_user_id);

create policy "family_members_update_own"
  on public.family_members for update
  using (auth.uid() = owner_user_id);

create policy "family_members_delete_own"
  on public.family_members for delete
  using (auth.uid() = owner_user_id);

create or replace function public.can_add_family_member()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid := auth.uid();
  cap int := 0;
  cnt int := 0;
  plan_slug text;
begin
  if pid is null then
    return jsonb_build_object('allowed', false, 'reason', 'not_authenticated');
  end if;

  insert into public.user_entitlements (user_id)
  values (pid)
  on conflict (user_id) do nothing;

  select ue.plan_slug into plan_slug
  from public.user_entitlements ue
  where ue.user_id = pid;

  select sp.max_family_members into cap
  from public.subscription_plans sp
  where sp.slug = plan_slug;

  select count(*)::int into cnt
  from public.family_members fm
  where fm.owner_user_id = pid;

  if cnt >= greatest(coalesce(cap, 0), 0) then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'member_limit_exceeded',
      'count', cnt,
      'limit', cap,
      'plan_slug', plan_slug
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'count', cnt,
    'limit', cap,
    'plan_slug', plan_slug
  );
end;
$$;

grant execute on function public.can_add_family_member() to authenticated;

create or replace function public.sync_ai_usage_month()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid := auth.uid();
begin
  if pid is null then
    return;
  end if;
  insert into public.user_entitlements (user_id)
  values (pid)
  on conflict (user_id) do nothing;

  update public.user_entitlements ue
  set
    ai_extractions_used = 0,
    usage_period_started_at = date_trunc('month', timezone('utc', now())),
    updated_at = now()
  where ue.user_id = pid
    and ue.usage_period_started_at < date_trunc('month', timezone('utc', now()));
end;
$$;

grant execute on function public.sync_ai_usage_month() to authenticated;

create table if not exists public.medicine_schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  family_member_id uuid references public.family_members (id) on delete set null,
  source text not null default 'manual' check (source in ('manual', 'prescription_generated')),
  prescription_id uuid references public.prescriptions (id) on delete set null,
  medication_line_index int,
  medication_name text not null,
  dosage_text text,
  meal_instruction text,
  schedule_kind text not null default 'daily' check (schedule_kind in ('daily', 'weekly', 'one_off')),
  time_points jsonb not null default '["09:00"]'::jsonb,
  weekdays jsonb default null,
  start_date date not null default (timezone('utc', now()))::date,
  end_date date,
  timezone text default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists medicine_schedules_user_day_idx on public.medicine_schedules (user_id, start_date);

alter table public.medicine_schedules enable row level security;

create policy "medicine_schedules_rw_own"
  on public.medicine_schedules for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
alter table public.prescriptions
  add column if not exists document_kind text not null default 'prescription'
    check (document_kind in ('prescription', 'report'));

alter table public.prescriptions
  add column if not exists report_summary jsonb;

create index if not exists prescriptions_kind_idx on public.prescriptions (user_id, document_kind, created_at desc);

-- Subscription catalog: public read of plan limits used by the app shell.
alter table public.subscription_plans enable row level security;

create policy "plans_select_all"
  on public.subscription_plans for select
  using (true);
