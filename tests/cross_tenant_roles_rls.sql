-- Six-role real-session RLS regression (verified against live Supabase 2026-11-19).
-- Entire test is transactional; test auth sessions are rolled back. No business data changes.
BEGIN;
CREATE TEMP TABLE ys_rls_test_users AS
 SELECT DISTINCT ON (p.workflow_role) p.workflow_role,p.user_id,p.branch_id,
 gen_random_uuid() sid
 FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id
 WHERE p.active AND b.company_id=1 AND b.active AND
 p.workflow_role IN ('manager','driver','supervisor','kitchen','callcenter_followup','complaints_officer')
 ORDER BY p.workflow_role,p.user_id;
CREATE TEMP TABLE ys_rls_foreign_branches AS
 SELECT id FROM public.dlv_branches WHERE company_id<>1 AND active;
CREATE TEMP TABLE ys_rls_test_results(
 role_name text,valid_session boolean,own_branch_allowed boolean,
 foreign_branch_grant_denied boolean,foreign_branches integer,
 foreign_orders integer,foreign_profiles integer,foreign_incidents integer);
GRANT SELECT ON ys_rls_test_users,ys_rls_foreign_branches TO authenticated;
GRANT INSERT,SELECT ON ys_rls_test_results TO authenticated;
DO $setup$
BEGIN
 IF (SELECT count(*) FROM ys_rls_test_users)<>6 OR
    NOT EXISTS (SELECT 1 FROM ys_rls_foreign_branches) OR
    NOT EXISTS (SELECT 1 FROM public.dlv_profiles WHERE branch_id IN
       (SELECT id FROM ys_rls_foreign_branches))
 THEN RAISE EXCEPTION 'Need six employee roles and a populated second tenant'; END IF;
END $setup$;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at)
 SELECT sid,user_id,now(),now() FROM ys_rls_test_users;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE u record; foreign_branch integer;
BEGIN
 SELECT min(id) INTO foreign_branch FROM ys_rls_foreign_branches;
 FOR u IN SELECT * FROM ys_rls_test_users LOOP
  PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',u.user_id::text,'session_id',u.sid::text,'role','authenticated',
    'exp',floor(extract(epoch FROM now()+interval '5 minutes')),'aal','aal1')::text,true);
  INSERT INTO ys_rls_test_results
  SELECT u.workflow_role,
   public.dlv_session_valid(),
   public.dlv_can_access_branch(u.branch_id),
   NOT public.dlv_can_access_branch(foreign_branch),
   (SELECT count(*) FROM public.dlv_branches WHERE id IN(SELECT id FROM ys_rls_foreign_branches)),
   (SELECT count(*) FROM public.dlv_orders WHERE branch_id IN(SELECT id FROM ys_rls_foreign_branches)),
   (SELECT count(*) FROM public.dlv_profiles WHERE branch_id IN(SELECT id FROM ys_rls_foreign_branches)),
   (SELECT count(*) FROM public.dlv_incidents WHERE branch_id IN(SELECT id FROM ys_rls_foreign_branches));
 END LOOP;
 IF EXISTS(SELECT 1 FROM ys_rls_test_results WHERE NOT valid_session OR
   NOT own_branch_allowed OR NOT foreign_branch_grant_denied OR foreign_branches<>0
   OR foreign_orders<>0 OR foreign_profiles<>0 OR foreign_incidents<>0)
 THEN RAISE EXCEPTION 'Cross-company RLS isolation failed'; END IF;
END $test$;
SELECT role_name,valid_session,own_branch_allowed,foreign_branch_grant_denied,
 foreign_branches,foreign_orders,foreign_profiles,foreign_incidents
 FROM ys_rls_test_results ORDER BY role_name;
ROLLBACK;
