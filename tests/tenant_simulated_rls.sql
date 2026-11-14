-- READ-ONLY tenant-isolation probe using a simulated auth.uid() for a non-admin user.
-- Privileged SQL-editor diagnostic ONLY; never expose impersonation capability to app users.
-- This tests one direction: company 1 -> company 12. It is NOT an end-to-end login test.
BEGIN READ ONLY;
SELECT set_config('request.jwt.claim.sub',(
 SELECT p.user_id::text FROM public.dlv_profiles p
 JOIN public.dlv_branches b ON b.id=p.branch_id
 WHERE p.active AND p.role <> 'admin' AND b.company_id=1
 ORDER BY p.user_id LIMIT 1
),true);
SET LOCAL ROLE authenticated;
SELECT
 auth.uid() IS NOT NULL AS simulated_identity,
 public.dlv_can_access_branch((SELECT id FROM public.dlv_branches WHERE company_id=12 ORDER BY id LIMIT 1)) AS other_tenant_branch_allowed,
 (SELECT count(*) FROM public.dlv_orders o JOIN public.dlv_branches b ON b.id=o.branch_id WHERE b.company_id=12) AS other_tenant_visible_orders,
 (SELECT count(*) FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id WHERE b.company_id=12) AS other_tenant_visible_profiles;
ROLLBACK;
-- PASS requires simulated_identity=true, other_tenant_branch_allowed=false,
-- other_tenant_visible_orders=0, other_tenant_visible_profiles=0.
-- Test is limited because company 12 currently has no active employees.
