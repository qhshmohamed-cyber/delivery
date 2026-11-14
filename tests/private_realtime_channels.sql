-- Verify join decisions with isolated JWT/session fixtures; everything is rolled back.
BEGIN;
CREATE TEMP TABLE rt_test_users AS SELECT p.user_id,p.role,p.workflow_role,p.branch_id,gen_random_uuid() sid FROM public.dlv_profiles p WHERE p.active;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at) SELECT sid,user_id,now(),now() FROM rt_test_users;
CREATE TEMP TABLE rt_test_results(test text,passed boolean,checked integer);
GRANT SELECT ON rt_test_users TO authenticated;
GRANT ALL ON rt_test_results TO authenticated;
DO $tests$
DECLARE u record; home_company bigint; c record; n integer:=0;
BEGIN
 FOR u IN SELECT * FROM rt_test_users LOOP
  SELECT company_id INTO home_company FROM public.dlv_branches WHERE id=u.branch_id;
  PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF NOT public.dlv_realtime_topic_allowed('profile:user:'||u.user_id) THEN RAISE EXCEPTION 'Own profile channel blocked';END IF;
  IF public.dlv_realtime_topic_allowed('profile:user:'||gen_random_uuid()) OR public.dlv_realtime_topic_allowed('orders:user:'||gen_random_uuid()) THEN RAISE EXCEPTION 'Other user topic permitted';END IF;
  IF public.dlv_realtime_topic_allowed('unknown') OR public.dlv_realtime_topic_allowed('brand:company:999999999') THEN RAISE EXCEPTION 'Unknown topic permitted';END IF;
  IF u.role<>'admin' AND public.dlv_realtime_topic_allowed('owner:user:'||u.user_id) THEN RAISE EXCEPTION 'Employee owner topic permitted';END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',gen_random_uuid(),'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
  IF public.dlv_realtime_topic_allowed('profile:user:'||u.user_id) THEN RAISE EXCEPTION 'Revoked session channel permitted'; END IF;
  EXECUTE 'RESET ROLE';n:=n+1;
 END LOOP;
 INSERT INTO rt_test_results VALUES('private_topics_user_owner_and_revoked_session_boundaries',true,n);
END $tests$;
SELECT * FROM rt_test_results;
ROLLBACK;
