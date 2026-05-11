-- When Pro is cancelled but the user already paid through current_end, we keep Pro until then.
alter table public.user_entitlements
  add column if not exists razorpay_pro_access_until timestamptz;

comment on column public.user_entitlements.razorpay_pro_access_until is 'End of current paid period (Razorpay current_end) while subscribed; or last access instant when cancelled-but-prepaid. Updated on webhooks / sync.';
