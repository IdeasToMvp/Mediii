-- ONE-OFF: set Pro + Razorpay linkage for a specific user (run in Supabase SQL Editor).
-- After running, you may delete this file or leave it out of git.

insert into public.user_entitlements (
  user_id,
  plan_slug,
  razorpay_customer_id,
  razorpay_subscription_id,
  razorpay_pro_access_until,
  updated_at
)
values (
  '89bf82a7-0b80-49f1-909f-1726734ae8c1'::uuid,
  'pro',
  'cust_SlNl7RpCp1IiBX',
  'sub_So0hpIjLmIjHtI',
  null,
  now()
)
on conflict (user_id) do update set
  plan_slug = excluded.plan_slug,
  razorpay_customer_id = excluded.razorpay_customer_id,
  razorpay_subscription_id = excluded.razorpay_subscription_id,
  razorpay_pro_access_until = excluded.razorpay_pro_access_until,
  updated_at = excluded.updated_at;

-- Verify:
-- select user_id, plan_slug, razorpay_customer_id, razorpay_subscription_id, razorpay_pro_access_until
-- from public.user_entitlements
-- where user_id = '89bf82a7-0b80-49f1-909f-1726734ae8c1';
