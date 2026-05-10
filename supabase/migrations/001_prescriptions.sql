-- Run in Supabase SQL Editor or via migrations
-- Table for MediBuddy prescriptions (RLS enforced per user)

create table if not exists public.prescriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text,
  patient_name text,
  doctor_name text,
  prescription_date text,
  diagnosis text,
  general_instructions text,
  medications jsonb not null default '[]'::jsonb,
  extraction_notes text,
  raw_analysis jsonb,
  source text not null default 'manual' check (source in ('manual', 'analyzed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists prescriptions_user_id_created_at_idx
  on public.prescriptions (user_id, created_at desc);

alter table public.prescriptions enable row level security;

create policy "prescriptions_select_own"
  on public.prescriptions for select
  using (auth.uid() = user_id);

create policy "prescriptions_insert_own"
  on public.prescriptions for insert
  with check (auth.uid() = user_id);

create policy "prescriptions_update_own"
  on public.prescriptions for update
  using (auth.uid() = user_id);

create policy "prescriptions_delete_own"
  on public.prescriptions for delete
  using (auth.uid() = user_id);
