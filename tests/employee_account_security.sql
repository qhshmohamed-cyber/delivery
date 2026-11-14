-- Database authorization simulation only, not a real password/MFA login.
-- All fixtures, credential changes and audit writes are rolled back.
BEGIN;
CREATE TEMP TABLE security_test_users AS
 SELECT p.user_id,p.role,p.workflow_role,p.branch_id,p.active,
 gen_random_uuid() sid FROM public.dlv_profiles p;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at)
 SELECT sid,user_id,now(),now() FROM security_test_users;
CREATE TEMP TABLE security_test_results(test text, passed boolean, checked integer);
GRANT SELECT ON security_test_users TO authenticated;
GRANT ALL ON security_test_results TO authenticated;
DO $tests$
DECLARE u record; v_expected text; forbidden integer; checked integer:=0; denied integer:=0;
BEGIN
 FOR u IN SELECT * FROM security_test_users WHERE role<>'admin' LOOP
  PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF NOT public.dlv_session_valid() THEN RAISE EXCEPTION 'Active fixture session denied'; END IF;
  SELECT (SELECT count(*) FROM public.dlv_branches b WHERE NOT public.dlv_can_access_branch(b.id))+
   (SELECT count(*) FROM public.dlv_orders o WHERE NOT public.dlv_can_access_branch(o.branch_id))+
   (SELECT count(*) FROM public.dlv_locations l WHERE NOT public.dlv_can_access_branch(l.branch_id))+
   (SELECT count(*) FROM public.dlv_profiles p WHERE p.user_id<>auth.uid() AND NOT public.dlv_can_access_branch(p.branch_id))
   INTO forbidden;
  IF forbidden<>0 THEN RAISE EXCEPTION 'Branch boundary failed'; END IF;
  IF public.dlv_role()='driver' AND EXISTS(SELECT 1 FROM public.dlv_orders WHERE driver_id IS DISTINCT FROM auth.uid()) THEN RAISE EXCEPTION 'Driver assignment boundary failed'; END IF;
  BEGIN
   PERFORM public.dlv_set_pilot_password(NULL,'Invalid-test-value');
   RAISE EXCEPTION 'Employee could reset another password';
  EXCEPTION WHEN insufficient_privilege THEN denied:=denied+1; END;
  BEGIN
   PERFORM public.dlv_create_account(NULL,NULL,NULL,NULL,NULL,NULL);
   RAISE EXCEPTION 'Employee could create an account';
  EXCEPTION WHEN insufficient_privilege THEN denied:=denied+1; END;
  -- A signed JWT referring to a nonexistent session must fail closed.
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',gen_random_uuid(),'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
  IF public.dlv_session_valid() OR public.dlv_role() IS NOT NULL OR public.dlv_wf() IS NOT NULL THEN RAISE EXCEPTION 'Revoked session accepted'; END IF;
  IF EXISTS(SELECT 1 FROM public.dlv_profiles) OR EXISTS(SELECT 1 FROM public.dlv_orders) THEN RAISE EXCEPTION 'Revoked session can read data'; END IF;
  checked:=checked+1;
  EXECUTE 'RESET ROLE';
 END LOOP;
 INSERT INTO security_test_results VALUES('employee_branch_driver_and_revoked_session_boundaries',true,checked),('employee_account_administration_denied',true,denied);
END $tests$;
DO $owner_tests$
DECLARE u record; target uuid; sid2 uuid; branch integer; em text; pw text;
BEGIN
 SELECT * INTO u FROM security_test_users WHERE role='admin' AND workflow_role='admin' LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Owner fixture missing'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(u.user_id,u.sid::text,now()+interval '10 minutes');
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Owner AAL1 bypass'; END IF;
 BEGIN
  PERFORM public.dlv_list_pilots(); RAISE EXCEPTION 'AAL1 can list staff';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal2')::text,true);
 SELECT b.id INTO branch FROM public.dlv_branches b JOIN public.dlv_companies c ON c.id=b.company_id WHERE b.active AND c.active AND c.onboarding_status='active' LIMIT 1;
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Verified owner blocked'; END IF;
 em:='security-check-'||gen_random_uuid()::text||'@example.invalid';pw:='T!'||gen_random_uuid()::text||'a7';
 target:=public.dlv_create_account(em,pw,'Security rollback fixture','SEC-'||left(gen_random_uuid()::text,12),'driver',branch);
 EXECUTE 'RESET ROLE';
 sid2:=gen_random_uuid();
 INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid2,target,now(),now());
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM public.dlv_set_pilot_password(target,'T!'||gen_random_uuid()::text||'a7');
 EXECUTE 'RESET ROLE';
 IF EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=target) THEN RAISE EXCEPTION 'Password reset did not revoke sessions'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=target) OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=target) THEN RAISE EXCEPTION 'Reset removed employee'; END IF;
 INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(gen_random_uuid(),target,now(),now());
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM public.dlv_set_pilot_email(target,'security-updated-'||gen_random_uuid()::text||'@example.invalid');
 EXECUTE 'RESET ROLE';
 IF EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=target) THEN RAISE EXCEPTION 'Email reset did not revoke sessions'; END IF;
 -- Password check with wrong attempts persists its counter and blocks brute force.
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR i IN 1..6 LOOP
  IF public.dlv_owner_page_unlock('incorrect-'||gen_random_uuid()::text) THEN RAISE EXCEPTION 'Wrong page password accepted'; END IF;
 END LOOP;
 EXECUTE 'RESET ROLE';
 IF NOT EXISTS(SELECT 1 FROM private.dlv_owner_unlock_attempts WHERE user_id=u.user_id AND attempts>=6) THEN RAISE EXCEPTION 'Unlock rate limit missing'; END IF;
 INSERT INTO security_test_results VALUES('owner_mfa_required_and_verified_owner_accepted',true,2),('credential_resets_revoke_sessions_preserve_account',true,2),('owner_unlock_attempt_limit',true,6);
END $owner_tests$;
SELECT * FROM security_test_results;
ROLLBACK;
