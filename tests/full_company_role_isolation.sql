BEGIN;
CREATE TEMP TABLE isolation_people AS SELECT p.user_id,p.workflow_role,p.role,p.branch_id,b.company_id,gen_random_uuid() sid FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id WHERE p.active AND p.role<>'admin';
CREATE TEMP TABLE isolation_branches AS SELECT id,company_id FROM public.dlv_branches;
CREATE TEMP TABLE isolation_summary(role_name text,accounts_checked int,foreign_branch_allowed int,foreign_rows_visible int);
INSERT INTO auth.sessions(id,user_id,created_at,updated_at) SELECT sid,user_id,now(),now() FROM isolation_people;
GRANT SELECT ON isolation_people,isolation_branches TO authenticated;GRANT ALL ON isolation_summary TO authenticated;
DO $test$
DECLARE u record; branch record; n int; visible_count int;
BEGIN
 FOR u IN SELECT * FROM isolation_people LOOP
  PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF NOT public.dlv_session_valid() OR public.dlv_role() IS NULL THEN RAISE EXCEPTION 'Test session not authorized';END IF;
  n:=0;
  FOR branch IN SELECT * FROM isolation_branches WHERE company_id<>u.company_id LOOP
   IF public.dlv_can_access_branch(branch.id) THEN n:=n+1;END IF;
   IF public.dlv_realtime_topic_allowed('brand:company:'||branch.company_id::text) THEN RAISE EXCEPTION 'Foreign brand channel permitted';END IF;
  END LOOP;
  SELECT (SELECT count(*) FROM public.dlv_orders o JOIN isolation_branches b ON b.id=o.branch_id WHERE b.company_id<>u.company_id)+(SELECT count(*) FROM public.dlv_profiles p JOIN isolation_branches b ON b.id=p.branch_id WHERE b.company_id<>u.company_id)+(SELECT count(*) FROM public.dlv_locations l JOIN isolation_branches b ON b.id=l.branch_id WHERE b.company_id<>u.company_id)+(SELECT count(*) FROM public.dlv_incidents i JOIN isolation_branches b ON b.id=i.branch_id WHERE b.company_id<>u.company_id) INTO visible_count;
  IF n<>0 OR visible_count<>0 THEN RAISE EXCEPTION 'Cross-company isolation failure';END IF;
  IF u.role='driver' AND EXISTS(SELECT 1 FROM public.dlv_orders WHERE driver_id IS DISTINCT FROM auth.uid()) THEN RAISE EXCEPTION 'Driver saw another driver order';END IF;
  INSERT INTO isolation_summary VALUES(u.workflow_role,1,n,visible_count);
  EXECUTE 'RESET ROLE';
 END LOOP;
END $test$;
SELECT role_name,sum(accounts_checked) accounts_checked,sum(foreign_branch_allowed) foreign_branch_allowed,sum(foreign_rows_visible) foreign_rows_visible FROM isolation_summary GROUP BY role_name ORDER BY role_name;
ROLLBACK;