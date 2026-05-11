-- Razorpay linkage on entitlements (updated only via service-role webhook / admin).

alter table public.user_entitlements
  add column if not exists razorpay_customer_id text,
  add column if not exists razorpay_subscription_id text;

comment on column public.user_entitlements.razorpay_customer_id is 'Razorpay customer id for recurring billing';
comment on column public.user_entitlements.razorpay_subscription_id is 'Active or last-known Razorpay subscription id';
