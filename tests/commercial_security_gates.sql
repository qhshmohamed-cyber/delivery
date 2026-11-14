-- Your Staff Delivery: read-only commercial security gate checks.
-- Run in Supabase SQL editor. No customer data is selected or modified.
-- A PASS means configuration verified, NOT a full penetration test.
WITH checks AS (
 SELECT 'public_tables_have_rls' AS check_name,
        NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity) AS pass,
        'All ordinary public tables must have RLS enabled' AS detail
 UNION ALL
 SELECT 'orders_branch_policy', EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='dlv_orders' AND cmd='SELECT' AND qual LIKE '%dlv_can_access_branch%'), 'Order SELECT must check branch'
 UNION ALL
 SELECT 'driver_own_orders', EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='dlv_orders' AND cmd='SELECT' AND qual LIKE '%driver_id%' AND qual LIKE '%auth.uid%'), 'Driver SELECT must check assigned driver'
 UNION ALL
 SELECT 'locations_branch_policy', EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='dlv_locations' AND cmd='SELECT' AND qual LIKE '%dlv_can_access_branch%'), 'Location SELECT must check branch'
 UNION ALL
 SELECT 'complaints_branch_policy', EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='dlv_incidents' AND cmd='SELECT' AND qual LIKE '%dlv_can_access_branch%'), 'Complaint SELECT must check branch'
 UNION ALL
 SELECT 'complaint_inbox_not_anonymous', NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='dlv_complaint_inbox' AND has_function_privilege('anon',p.oid,'EXECUTE')), 'Complaint inbox cannot be executed anonymously'
 UNION ALL
 SELECT 'driver_location_not_anonymous', NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='dlv_update_location' AND has_function_privilege('anon',p.oid,'EXECUTE')), 'Location update cannot be executed anonymously'
 UNION ALL
 SELECT 'multi_tenant_test_possible', (SELECT count(*)>=2 FROM public.dlv_companies), 'Two companies exist; still requires actual account isolation tests'
)
SELECT check_name,CASE WHEN pass THEN 'PASS' ELSE 'FAIL' END status,detail FROM checks ORDER BY check_name;
