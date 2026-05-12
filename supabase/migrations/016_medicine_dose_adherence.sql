-- Per-dose adherence for expanded medicine occurrences (synthetic occurrence_key from app/API).

create table if not exists public.medicine_dose_adherence (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  schedule_id uuid not null references public.medicine_schedules (id) on delete cascade,
  occurrence_key text not null,
  due_at_iso timestamptz not null,
  record_kind text not null check (record_kind in ('user_taken', 'auto_taken')),
  recorded_at timestamptz not null default now(),
  unique (user_id, occurrence_key)
);

create index if not exists medicine_dose_adherence_user_due_idx
  on public.medicine_dose_adherence (user_id, due_at_iso);

alter table public.medicine_dose_adherence enable row level security;

create policy "medicine_dose_adherence_rw_own"
  on public.medicine_dose_adherence for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
