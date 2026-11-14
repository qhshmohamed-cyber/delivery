BEGIN;
CREATE TEMP TABLE complaint_checks(test text,passed boolean);
DO $test$
DECLARE own uuid;officer uuid;mgr uuid;sid uuid;branch integer;other_branch integer;oid bigint;oldoid bigint;cid bigint;req uuid:=gen_random_uuid();answer jsonb;summary jsonb;day date:=public.dlv_operational_day(now());num text:='QA-'||left(gen_random_uuid()::text,12);r record;
BEGIN
 SELECT user_id INTO STRICT own FROM public.dlv_profiles WHERE active AND role='admin' AND workflow_role='admin';
 SELECT p.user_id,p.branch_id INTO STRICT officer,branch FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id JOIN public.dlv_companies c ON c.id=b.company_id WHERE p.active AND p.role<>'admin' AND b.active AND c.active AND c.onboarding_status='active' LIMIT 1;
 UPDATE public.dlv_profiles SET role='manager',workflow_role='complaints_officer' WHERE user_id=officer;
 INSERT INTO public.dlv_orders(branch_id,order_no,order_date,created_by) VALUES(branch,num,day,officer) RETURNING id INTO oid;
 INSERT INTO public.dlv_orders(branch_id,order_no,order_date,created_by,created_at) VALUES(branch,num,day-1,officer,now()-interval '1 day') RETURNING id INTO oldoid;
 sid:=gen_random_uuid();INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid,officer,now(),now());
 PERFORM set_config('request.jwt.claim.sub',officer::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',officer,'session_id',sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 answer:=public.dlv_register_complaint_by_order(req,branch,day,num,'شكوى اختبار','تفاصيل خاصة <script>','high','resolved','تم التواصل مع العميل واستبدال الطلب برضاه');cid:=(answer->>'id')::bigint;
 IF NOT (public.dlv_register_complaint_by_order(req,branch,day,num,'شكوى اختبار','تفاصيل خاصة <script>','high','resolved','تم التواصل مع العميل واستبدال الطلب برضاه')->>'replayed')::boolean THEN RAISE EXCEPTION 'Duplicate retry not detected';END IF;
 BEGIN PERFORM public.dlv_register_complaint_by_order(req,branch,day,num,'شكوى مختلفة','تفاصيل خاصة <script>','high','resolved','تم التواصل مع العميل واستبدال الطلب برضاه');RAISE EXCEPTION 'Mismatched retry accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.dlv_register_complaint_by_order(gen_random_uuid(),branch,day,num,'شكوى اختبار','','high','resolved','');RAISE EXCEPTION 'Empty resolution accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.dlv_register_complaint_by_order(gen_random_uuid(),branch,day,'NOT-FOUND','شكوى اختبار','','high','open','جار التواصل');RAISE EXCEPTION 'Unknown order accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.dlv_daily_complaint_summary(branch,day);RAISE EXCEPTION 'Officer got management report';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 EXECUTE 'RESET ROLE';
 IF NOT EXISTS(SELECT 1 FROM public.dlv_incidents WHERE id=cid AND order_id=oid AND status='resolved' AND created_by=officer AND followup_by=officer AND resolved_at IS NOT NULL) THEN RAISE EXCEPTION 'Complaint data incomplete';END IF;
 IF (SELECT count(*) FROM public.dlv_complaint_actions WHERE incident_id=cid)<>1 THEN RAISE EXCEPTION 'Duplicate action created';END IF;
 -- An older complaint receives an action today and must appear in today's actions.
 INSERT INTO public.dlv_incidents(branch_id,order_id,title,details,status,created_by,category,created_at) VALUES(branch,oldoid,'شكوى قديمة اختبار','','open',officer,'customer_complaint',now()-interval '1 day') RETURNING id INTO cid;
 EXECUTE 'SET LOCAL ROLE authenticated';PERFORM public.dlv_complaint_followup(cid,'تم حل الشكوى القديمة اليوم','resolved');EXECUTE 'RESET ROLE';
 -- Manager for this branch sees the report, another branch is denied.
 UPDATE public.dlv_profiles SET role='manager',workflow_role='manager' WHERE user_id=officer;
 EXECUTE 'SET LOCAL ROLE authenticated';summary:=public.dlv_daily_complaint_summary(branch,day);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(summary->'items')x WHERE x->>'order_no'=num AND x->>'action'='تم التواصل مع العميل واستبدال الطلب برضاه') THEN RAISE EXCEPTION 'Resolution absent from report';END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(summary->'actions')x WHERE x->>'complaint_id'=cid::text AND x->>'action'='تم حل الشكوى القديمة اليوم') THEN RAISE EXCEPTION 'Older complaint action missing';END IF;
 EXECUTE 'RESET ROLE';
 SELECT b.id INTO other_branch FROM public.dlv_branches b WHERE b.id<>branch LIMIT 1;
 IF other_branch IS NOT NULL THEN EXECUTE 'SET LOCAL ROLE authenticated';BEGIN PERFORM public.dlv_daily_complaint_summary(other_branch,day);RAISE EXCEPTION 'Cross branch report leaked';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';END IF;
 -- Every ordinary role is denied complaint creation even with a valid session.
 FOR r IN SELECT user_id FROM public.dlv_profiles WHERE active AND workflow_role NOT IN ('admin','manager','complaints_officer') LOOP
  sid:=gen_random_uuid();INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid,r.user_id,now(),now());
  PERFORM set_config('request.jwt.claim.sub',r.user_id::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',r.user_id,'session_id',sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';BEGIN PERFORM public.dlv_register_complaint_by_order(gen_random_uuid(),branch,day,num,'غير مصرح','','medium','open','غير مصرح');RAISE EXCEPTION 'Unauthorized role registered complaint';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';
 END LOOP;
 -- Owner with page lock closed cannot see complaint report; unlocked owner can.
 sid:=gen_random_uuid();INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid,own,now(),now());
 PERFORM set_config('request.jwt.claim.sub',own::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',own,'session_id',sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';BEGIN PERFORM public.dlv_daily_complaint_summary(branch,day);RAISE EXCEPTION 'Locked owner report allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';
 INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(own,sid::text,now()+interval '15 minutes');
 EXECUTE 'SET LOCAL ROLE authenticated';summary:=public.dlv_daily_complaint_summary(branch,day);EXECUTE 'RESET ROLE';
 EXECUTE 'SET LOCAL ROLE anon';BEGIN PERFORM public.dlv_daily_complaint_summary(branch,day);RAISE EXCEPTION 'Anonymous report allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';
 INSERT INTO complaint_checks VALUES('officer_registration_order_day_and_resolution',true),('idempotent_retry_and_one_action',true),('missing_order_and_empty_action_rejected',true),('manager_and_unlocked_owner_report',true),('old_complaint_today_action_in_daily_report',true),('cross_branch_ordinary_roles_locked_owner_anon_denied',true);
END $test$;
SELECT * FROM complaint_checks;
ROLLBACK;

-- All credential mutations, attempts, and sessions in this test roll back.
BEGIN;
CREATE TEMP TABLE password_checks(test text,passed boolean);
DO $qa$
DECLARE own uuid; sid uuid:=gen_random_uuid();target uuid;v text;answer jsonb;weak text:='Password123!';test_current text:='Qa!'||encode(extensions.gen_random_bytes(20),'hex')||'A';test_new text:='Qb!'||encode(extensions.gen_random_bytes(20),'hex')||'B';i integer;
BEGIN
 BEGIN PERFORM private.dlv_checked_password_hash(weak);RAISE EXCEPTION 'Leaked password accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM private.dlv_checked_password_hash('short');RAISE EXCEPTION 'Short password accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM private.dlv_checked_password_hash(repeat('A',72)||'a1!');RAISE EXCEPTION 'Overlong bcrypt input accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 SELECT user_id INTO STRICT own FROM public.dlv_profiles WHERE active AND role='admin' AND workflow_role='admin';
 SELECT user_id INTO STRICT target FROM public.dlv_profiles WHERE active AND role<>'admin' LIMIT 1;
 INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid,own,now(),now());
 PERFORM set_config('request.jwt.claim.sub',own::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',own,'session_id',sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';BEGIN PERFORM public.dlv_owner_change_login_password(test_current,test_new);RAISE EXCEPTION 'Locked owner changed password';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';
 INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(own,sid::text,now()+interval '15 minutes');
 UPDATE auth.users SET encrypted_password=extensions.crypt(test_current,extensions.gen_salt('bf',12)) WHERE id=own;
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR i IN 1..5 LOOP answer:=public.dlv_owner_change_login_password('IncorrectFixture!',test_new);IF (answer->>'success')::boolean THEN RAISE EXCEPTION 'Incorrect current password accepted';END IF;END LOOP;
 answer:=public.dlv_owner_change_login_password(test_current,test_new);IF (answer->>'success')::boolean THEN RAISE EXCEPTION 'Rate limit bypass';END IF;
 EXECUTE 'RESET ROLE';DELETE FROM private.dlv_password_attempts WHERE user_id=own;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.dlv_owner_change_login_password(test_current,weak);RAISE EXCEPTION 'Owner set leaked password';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.dlv_set_pilot_password(target,weak);RAISE EXCEPTION 'Employee reset accepted leaked password';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 answer:=public.dlv_owner_change_login_password(test_current,test_new);IF NOT (answer->>'success')::boolean THEN RAISE EXCEPTION 'Valid password failed';END IF;
 EXECUTE 'RESET ROLE';SELECT encrypted_password INTO v FROM auth.users WHERE id=own;
 IF extensions.crypt(test_new,v)<>v OR v NOT LIKE '$2a$12$%' THEN RAISE EXCEPTION 'Password not hashed with cost 12';END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions WHERE id=sid) OR EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=own AND id<>sid) THEN RAISE EXCEPTION 'Session revocation incorrect';END IF;
 EXECUTE 'SET LOCAL ROLE authenticated';BEGIN PERFORM private.dlv_checked_password_hash(test_new);RAISE EXCEPTION 'Private checker publicly callable';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';
 EXECUTE 'SET LOCAL ROLE anon';BEGIN PERFORM public.dlv_owner_change_login_password(test_current,test_new);RAISE EXCEPTION 'Anonymous password change';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';
 INSERT INTO password_checks VALUES('known_leaked_weak_and_over72byte_denied',true),('owner_current_password_and_5_attempt_limit',true),('owner_lock_and_private_checker_access',true),('owner_and_employee_reset_reject_leaked_password',true),('random_password_accepted_bcrypt12',true),('other_sessions_revoked_current_preserved',true),('anonymous_denied',true);
END $qa$;
SELECT * FROM password_checks;
ROLLBACK;
