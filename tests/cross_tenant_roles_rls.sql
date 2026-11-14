-- Read-only cross-company RLS regression. Execute as database admin in a transaction.
-- Never print employee identifiers; no data is modified.
BEGIN;
CREATE TEMP TABLE dlv_rls_test_users AS
 SELECT DISTINCT ON (p.workflow_role) p.workflow_role,p.user_id
 FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id
 WHERE p.active AND b.company_id=1 AND p.workflow_role IN
 ('manager','driver','supervisor','kitchen','callcenter_followup','complaints_officer')
 ORDER BY p.workflow_role,p.user_id;
CREATE TEMP TABLE dlv_rls_test_results(role_name text,foreign_branches int,foreign_orders int,foreign_profiles int,foreign_incidents int);
GRANT SELECT ON dlv_rls_test_users TO authenticated;
GRANT INSERT,SELECT ON dlv_rls_test_results TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
DECLARE u record; v integer;
BEGIN
 FOR u IN SELECT * FROM dlv_rls_test_users LOOP
  PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);
  INSERT INTO dlv_rls_test_results
  SELECT u.workflow_role,
   (SELECT count(*) FROM public.dlv_branches WHERE company_id=12),
   (SELECT count(*) FROM public.dlv_orders WHERE branch_id IN(SELECT id FROM public.dlv_branches WHERE company_id=12)),
   (SELECT count(*) FROM public.dlv_profiles WHERE branch_id IN(3,4)),
   (SELECT count(*) FROM public.dlv_incidents WHERE branch_id IN(3,4));
 END LOOP;
 SELECT count(*) INTO v FROM dlv_rls_test_results
 WHERE foreign_branches<>0 OR foreign_orders<>0 OR foreign_profiles<>0 OR foreign_incidents<>0;
 IF v>0 THEN RAISE EXCEPTION 'Cross-tenant RLS regression: % failed roles',v;END IF;
END $$;
SELECT role_name,foreign_branches,foreign_orders,foreign_profiles,foreign_incidents FROM dlv_rls_test_results ORDER BY role_name;
ROLLBACK;