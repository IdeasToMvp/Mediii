-- Two tiers only: Free (2 household profiles) and Pro (10). Removes Plus.
-- Anyone on `plus` is moved to `pro` so billing stays paid.

update public.user_entitlements
set plan_slug = 'pro', updated_at = now()
where plan_slug = 'plus';

delete from public.subscription_plans where slug = 'plus';

update public.subscription_plans
set display_name = 'Free', max_family_members = 2, monthly_ai_extractions = 5
where slug = 'free';

update public.subscription_plans
set display_name = 'Pro', max_family_members = 10, monthly_ai_extractions = 100
where slug = 'pro';

comment on table public.subscription_plans is 'Catalog: free (2 family slots, 5 AI/mo) and pro (10 family slots, 100 AI/mo).';
