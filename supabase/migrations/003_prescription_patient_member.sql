-- Link extracted patient names to household family profiles (optional FK).
alter table public.prescriptions
  add column if not exists patient_family_member_id uuid references public.family_members (id) on delete set null;

create index if not exists prescriptions_patient_fm_idx on public.prescriptions (user_id, patient_family_member_id);
