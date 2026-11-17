-- Your Staff Delivery GPS privacy: read-only DB structural checks.
-- No customer records are returned or changed. Requires separate physical-device E2E tests.
WITH checks(test_name, passed) AS (
 VALUES
 ('one navigation row per driver (primary key)', EXISTS (
   SELECT 1 FROM pg_constraint k JOIN pg_class c ON k.conrelid=c.oid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='private' AND c.relname='dlv_driver_active_navigation' AND k.contype='p' AND pg_get_constraintdef(k.oid)='PRIMARY KEY (driver_id)'
 )),
 ('no duplicate active navigation', NOT EXISTS (SELECT 1 FROM private.dlv_driver_active_navigation GROUP BY driver_id HAVING count(*)>1)),
 ('no orphaned or cross-order navigation', NOT EXISTS (
   SELECT 1 FROM private.dlv_driver_active_navigation n LEFT JOIN public.dlv_orders o ON o.id=n.order_id
   WHERE o.id IS NULL OR o.driver_id IS DISTINCT FROM n.driver_id OR o.branch_id IS DISTINCT FROM n.branch_id OR o.status IS DISTINCT FROM 'out'
 )),
 ('anonymous cannot select driver navigation', NOT has_function_privilege('anon','public.dlv_begin_customer_navigation(bigint)','EXECUTE')
  AND NOT has_function_privilege('anon','public.dlv_stop_customer_navigation(bigint)','EXECUTE')
  AND NOT has_function_privilege('anon','public.dlv_current_customer_navigation()','EXECUTE')),
 ('anonymous cannot write GPS', NOT has_function_privilege('anon','public.dlv_update_location_v2(double precision,double precision,real,timestamp with time zone)','EXECUTE')),
 ('GPS table RLS and branch filter', EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='dlv_locations' AND rowsecurity)
  AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='dlv_locations' AND policyname='l_sel' AND qual LIKE '%dlv_can_access_branch%')
  AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='dlv_locations' AND policyname='dlv_live_session_boundary' AND permissive='RESTRICTIVE')),
 ('public track filtered by active destination', position('private.dlv_driver_active_navigation' IN pg_get_functiondef('public.dlv_track(text)'::regprocedure))>0 AND position('n.order_id=o.id' IN pg_get_functiondef('public.dlv_track(text)'::regprocedure))>0),
 ('alternative public track filtered by active destination', position('private.dlv_driver_active_navigation' IN pg_get_functiondef('public.dlv_customer_track(text,text)'::regprocedure))>0 AND position('n.order_id=o.id' IN pg_get_functiondef('public.dlv_customer_track(text,text)'::regprocedure))>0),
 ('order state changes trigger route cleanup', EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.dlv_orders'::regclass AND t.tgname='dlv_order_nav_cleanup' AND t.tgenabled <> 'D')),
 ('GPS rejects old samples and imprecise fixes', position('20 seconds' IN pg_get_functiondef('private.dlv_write_location(double precision,double precision,real,timestamp with time zone)'::regprocedure))>0 AND position('150' IN pg_get_functiondef('private.dlv_write_location(double precision,double precision,real,timestamp with time zone)'::regprocedure))>0),
 ('manager complaint receipt owned by manager', position('r.manager_id=auth.uid()' IN pg_get_functiondef('public.dlv_list_read_complaints(integer)'::regprocedure))>0)
)
SELECT test_name,passed FROM checks ORDER BY test_name;
