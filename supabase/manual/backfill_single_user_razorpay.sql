-- -----------------------------------------------------------------------------
-- ONE-OFF FIX (run manually in Supabase SQL Editor)
-- Do not commit real UUIDs or Razorpay ids into the repo.
--
-- Use when a user already has (or should have) Razorpay linkage but entitlements
-- are wrong: e.g. paid in Razorpay but plan still "free", or customer id typo.
--
-- Required info:
--   1) user_id  — UUID from auth.users / Dashboard → Authentication → Users
--   2) razorpay_customer_id — from Razorpay Dashboard → Customers (starts with cust_)
--   3) (optional) razorpay_subscription_id — sub_… if you want the row linked
--   4) (optional) plan_slug — 'pro' or 'free'
--   5) (optional) razorpay_pro_access_until — timestamptz if they cancelled but prepaid until a date
-- -----------------------------------------------------------------------------

-- Example A: only ensure customer id is stored (user already known to Razorpay)
/*
update public.user_entitlements
set
  razorpay_customer_id = 'cust_REPLACE_ME',
  updated_at = now()
where user_id = 'REPLACE_USER_UUID'::uuid;
*/

-- Example B: set Pro + subscription id (after you confirm sub is active in Razorpay Dashboard)
/*
update public.user_entitlements
set
  plan_slug = 'pro',
  razorpay_customer_id = coalesce(razorpay_customer_id, 'cust_REPLACE_ME'),
  razorpay_subscription_id = 'sub_REPLACE_ME',
  razorpay_pro_access_until = null,
  updated_at = now()
where user_id = 'REPLACE_USER_UUID'::uuid;
*/

-- Example C: user cancelled auto-renew but prepaid until period end — set end from Razorpay subscription "current_end" (unix seconds → timestamptz)
/*
update public.user_entitlements
set
  plan_slug = 'pro',
  razorpay_customer_id = coalesce(razorpay_customer_id, 'cust_REPLACE_ME'),
  razorpay_subscription_id = 'sub_REPLACE_ME',
  razorpay_pro_access_until = to_timestamp(1735689600), -- replace with their current_end from Razorpay API (seconds)
  updated_at = now()
where user_id = 'REPLACE_USER_UUID'::uuid;
*/

-- Verify before/after:
-- select user_id, plan_slug, razorpay_customer_id, razorpay_subscription_id, razorpay_pro_access_until, updated_at
-- from public.user_entitlements where user_id = 'REPLACE_USER_UUID'::uuid;
