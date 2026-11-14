-- Role isolation regression tests. READ ONLY, SQL editor only.
-- Simulates JWT subject for a real active user without exposing their ID.
-- Must never be exposed to application clients or used for writes.

-- Driver: assigned orders only; cannot read other driver locations or staff profiles.
BEGIN READ ONLY;
SELECT set_config('request.jwt.claim.sub',(
 SELECT p.user_id::text FROM public.dlv_profiles p
 LEFT JOIN public.dlv_orders o ON o.driver_id=p.user_id
 WHERE p.active AND p.role='driver' AND p.workflow_role='driver'
 GROUP BY p.user_id ORDER BY count(o.id) DESC,p.user_id LIMIT 1),true);
SET LOCAL ROLE authenticated;
SELECT public.dlv_role() AS expected_driver,
 (SELECT count(*) FROM public.dlv_orders WHERE driver_id IS DISTINCT FROM auth.uid()) AS other_driver_orders_visible,
 (SELECT count(*) FROM public.dlv_locations WHERE driver_id IS DISTINCT FROM auth.uid()) AS other_driver_locations_visible,
 (SELECT count(*) FROM public.dlv_profiles WHERE user_id IS DISTINCT FROM auth.uid()) AS other_profiles_visible;
ROLLBACK;
-- PASS: role=driver; all counts=0.

-- Manager: no rows from branches not permitted by the same RLS branch guard.
BEGIN READ ONLY;
SELECT set_config('request.jwt.claim.sub',(
 SELECT p.user_id::text FROM public.dlv_profiles p
 WHERE p.active AND p.workflow_role='manager' ORDER BY p.user_id LIMIT 1),true);
SET LOCAL ROLE authenticated;
SELECT public.dlv_role() AS expected_manager,
 (SELECT count(*) FROM public.dlv_orders o WHERE NOT public.dlv_can_access_branch(o.branch_id)) AS forbidden_orders_visible,
 (SELECT count(*) FROM public.dlv_locations l WHERE NOT public.dlv_can_access_branch(l.branch_id)) AS forbidden_locations_visible,
 (SELECT count(*) FROM public.dlv_incidents i WHERE NOT public.dlv_can_access_branch(i.branch_id)) AS forbidden_incidents_visible,
 (SELECT count(*) FROM public.dlv_profiles p WHERE p.user_id IS DISTINCT FROM auth.uid() AND NOT public.dlv_can_access_branch(p.branch_id)) AS forbidden_profiles_visible;
ROLLBACK;
-- PASS: role=manager; all counts=0.
-- WARNING: role and workflow_role are distinct fields. Filter workflow_role for manager tests.
-- These tests do not replace independent end-to-end logins from two tenant companies.
