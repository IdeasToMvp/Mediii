-- Cap Pro at 100 AI document extractions per UTC month (same mechanism as Free).
-- -1 meant unlimited; we replace with a fixed cap for cost control.

update public.subscription_plans
set monthly_ai_extractions = 100
where slug = 'pro';

comment on table public.subscription_plans is 'Catalog: free (2 family slots, 5 AI/mo) and pro (10 family slots, 100 AI/mo).';
