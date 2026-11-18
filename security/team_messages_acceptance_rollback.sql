-- All synthetic accounts, presence, messages and broadcasts are rolled back.
CREATE TEMP TABLE qa_team_results(test text,passed boolean) ON COMMIT DROP;
DO $$
DECLARE company_a bigint;company_b bigint;branch_a integer;branch_b integer;branch_c integer;
 manager_id uuid:=gen_random_uuid();driver_a uuid:=gen_random_uuid();driver_b uuid:=gen_random_uuid();driver_c uuid:=gen_random_uuid();
 uid uuid;sid uuid;owner_id uuid;owner_sid uuid:=gen_random_uuid();request_id uuid:=gen_random_uuid();mid uuid;copy_id uuid;n bigint;summary jsonb;
 original_users bigint;original_messages bigint;
BEGIN
 SELECT count(*) INTO original_users FROM auth.users;SELECT count(*) INTO original_messages FROM private.dlv_team_messages;
 SELECT user_id INTO STRICT owner_id FROM public.dlv_profiles WHERE active AND role='admin' AND workflow_role='admin' LIMIT 1;
 BEGIN
  INSERT INTO public.dlv_companies(name,slug,active,onboarding_status) VALUES('QA team A','qa-a-'||gen_random_uuid(),true,'active') RETURNING id INTO company_a;
  INSERT INTO public.dlv_companies(name,slug,active,onboarding_status) VALUES('QA team B','qa-b-'||gen_random_uuid(),true,'active') RETURNING id INTO company_b;
  SELECT coalesce(max(id),0)+1 INTO branch_a FROM public.dlv_branches;branch_b:=branch_a+1;branch_c:=branch_a+2;
  INSERT INTO public.dlv_branches(id,name,company_id,active) VALUES(branch_a,'QA A1',company_a,true),(branch_b,'QA A2',company_a,true),(branch_c,'QA B1',company_b,true);
  CREATE TEMP TABLE qa_team_sessions(user_id uuid,session_id uuid) ON COMMIT DROP;
  FOREACH uid IN ARRAY ARRAY[manager_id,driver_a,driver_b,driver_c] LOOP
   INSERT INTO auth.users(id,email,aud,role,created_at,updated_at) VALUES(uid,'qa-'||uid||'@example.com','authenticated','authenticated',now(),now());
   INSERT INTO public.dlv_profiles(user_id,employee_code,full_name,branch_id,allowed_branch_ids,role,workflow_role)
   VALUES(uid,'QA-'||substr(uid::text,1,20),'QA employee',CASE WHEN uid=driver_b THEN branch_b WHEN uid=driver_c THEN branch_c ELSE branch_a END,
   ARRAY[CASE WHEN uid=driver_b THEN branch_b WHEN uid=driver_c THEN branch_c ELSE branch_a END],CASE WHEN uid=manager_id THEN 'manager' ELSE 'driver' END,CASE WHEN uid=manager_id THEN 'manager' ELSE 'driver' END);
   sid:=gen_random_uuid();INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid,uid,now(),now());INSERT INTO qa_team_sessions VALUES(uid,sid);
  END LOOP;
  uid:=driver_a;SELECT s.session_id INTO sid FROM qa_team_sessions s WHERE s.user_id=uid;
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'session_id',sid,'exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
  PERFORM public.dlv_team_ping(true);
  BEGIN PERFORM public.dlv_team_members();RAISE EXCEPTION 'Employee read manager roster';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  BEGIN PERFORM public.dlv_team_send(manager_id,'unauthorized',gen_random_uuid());RAISE EXCEPTION 'Employee sent management message';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  INSERT INTO qa_team_results VALUES('employee cannot enumerate or send',true);

  uid:=manager_id;SELECT s.session_id INTO sid FROM qa_team_sessions s WHERE s.user_id=uid;
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'session_id',sid,'exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
  IF (SELECT count(*) FROM public.dlv_team_members())<>1 OR NOT EXISTS(SELECT 1 FROM public.dlv_team_members() x WHERE x.user_id=driver_a AND x.online AND x.visible) THEN RAISE EXCEPTION 'Roster scope or presence failed';END IF;
  UPDATE private.dlv_team_presence SET last_seen=now()-interval '2 minutes' WHERE user_id=driver_a;
  IF EXISTS(SELECT 1 FROM public.dlv_team_members() x WHERE x.user_id=driver_a AND x.online) THEN RAISE EXCEPTION 'Stale presence reported online';END IF;
  UPDATE private.dlv_team_presence SET last_seen=now(),visible=false WHERE user_id=driver_a;
  IF NOT EXISTS(SELECT 1 FROM public.dlv_team_members() x WHERE x.user_id=driver_a AND x.online AND NOT x.visible) THEN RAISE EXCEPTION 'Background presence failed';END IF;
  mid:=public.dlv_team_send(driver_a,'QA private management message',request_id);
  copy_id:=public.dlv_team_send(driver_a,'QA private management message',request_id);
  IF mid<>copy_id OR (SELECT count(*) FROM private.dlv_team_messages WHERE sender_id=manager_id)<>1 THEN RAISE EXCEPTION 'Idempotency failed';END IF;
  BEGIN PERFORM public.dlv_team_send(driver_a,'changed payload',request_id);RAISE EXCEPTION 'Reused request accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN PERFORM public.dlv_team_send(driver_b,'wrong branch',gen_random_uuid());RAISE EXCEPTION 'Same-company branch bypass';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  BEGIN PERFORM public.dlv_team_send(driver_c,'wrong company',gen_random_uuid());RAISE EXCEPTION 'Cross-company bypass';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  BEGIN PERFORM public.dlv_team_send(driver_a,repeat('x',2001),gen_random_uuid());RAISE EXCEPTION 'Oversize accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  INSERT INTO qa_team_results VALUES('manager scope, fresh/background/stale presence, idempotent send',true);

  uid:=driver_b;SELECT s.session_id INTO sid FROM qa_team_sessions s WHERE s.user_id=uid;
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'session_id',sid,'exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
  IF EXISTS(SELECT 1 FROM public.dlv_team_inbox()) OR public.dlv_team_ack(mid,true) THEN RAISE EXCEPTION 'Other employee read or acknowledged message';END IF;
  uid:=driver_a;SELECT s.session_id INTO sid FROM qa_team_sessions s WHERE s.user_id=uid;
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'session_id',sid,'exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
  IF (SELECT count(*) FROM public.dlv_team_inbox())<>1 OR NOT public.dlv_team_ack(mid,false) OR NOT public.dlv_team_ack(mid,true) THEN RAISE EXCEPTION 'Recipient delivery/read failed';END IF;
  IF public.dlv_team_ack(mid,true) THEN RAISE EXCEPTION 'Duplicate read rewrote receipt';END IF;
  INSERT INTO qa_team_results VALUES('recipient-only inbox, delivery and stable read receipts',true);
  uid:=manager_id;SELECT s.session_id INTO sid FROM qa_team_sessions s WHERE s.user_id=uid;
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'session_id',sid,'exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
  IF NOT EXISTS(SELECT 1 FROM public.dlv_team_thread(driver_a) x WHERE x.id=mid AND x.delivered_at IS NOT NULL AND x.read_at IS NOT NULL) THEN RAISE EXCEPTION 'Sender cannot see receipts';END IF;
  DELETE FROM auth.sessions WHERE user_id=driver_a;
  IF EXISTS(SELECT 1 FROM public.dlv_team_members() x WHERE x.user_id=driver_a AND x.online) THEN RAISE EXCEPTION 'Logged out session appears online';END IF;
  INSERT INTO qa_team_results VALUES('logout removes online status and sender sees receipts',true);
  IF has_table_privilege('authenticated','private.dlv_team_messages','SELECT') OR has_table_privilege('anon','private.dlv_team_presence','SELECT') THEN RAISE EXCEPTION 'Raw private data exposed';END IF;

  INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(owner_sid,owner_id,now(),now());
  PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'session_id',owner_sid,'exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
  BEGIN PERFORM public.dlv_team_members();RAISE EXCEPTION 'Locked owner used roster';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(owner_id,owner_sid::text,now()+interval '15 minutes');
  IF NOT EXISTS(SELECT 1 FROM public.dlv_team_members('QA employee') x WHERE x.user_id=driver_c) THEN RAISE EXCEPTION 'Owner missing other company';END IF;
  PERFORM public.dlv_team_send(driver_c,'QA owner notice',gen_random_uuid());
  INSERT INTO qa_team_results VALUES('owner lock enforced; unlocked owner spans companies; raw tables private',true);
  SELECT jsonb_agg(to_jsonb(r)) INTO summary FROM qa_team_results r;
  RAISE EXCEPTION USING ERRCODE='ZQ004',MESSAGE='rollback team QA fixtures';
 EXCEPTION WHEN SQLSTATE 'ZQ004' THEN NULL;
 END;
 IF (SELECT count(*) FROM auth.users)<>original_users OR (SELECT count(*) FROM private.dlv_team_messages)<>original_messages THEN RAISE EXCEPTION 'Fixture rollback failed';END IF;
 INSERT INTO qa_team_results SELECT * FROM jsonb_to_recordset(summary) AS x(test text,passed boolean);
END $$;
SELECT * FROM qa_team_results;
