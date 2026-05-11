-- Clarify razorpay_pro_access_until semantics (column already exists from 009).
comment on column public.user_entitlements.razorpay_pro_access_until is 'End of current paid period (Razorpay current_end) while subscribed; or last access instant when cancelled-but-prepaid. Updated on webhooks / sync.';
