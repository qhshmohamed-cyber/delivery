-- Read-only check: an authenticated PostgreSQL role with no valid auth.uid()
-- must not see production customer/staff/order/location/complaint rows.
-- Run as one statement in Supabase SQL editor. It does NOT test a real signed-in user.
BEGIN READ ONLY;
SET LOCAL ROLE authenticated;
SELECT 'orders' AS resource, count(*) AS visible_rows FROM public.dlv_orders
UNION ALL SELECT 'profiles',count(*) FROM public.dlv_profiles
UNION ALL SELECT 'locations',count(*) FROM public.dlv_locations
UNION ALL SELECT 'incidents',count(*) FROM public.dlv_incidents;
ROLLBACK;
-- Expected: zero for all four resources. A nonzero result is a release blocker.
