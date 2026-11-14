BEGIN;
CREATE TEMP TABLE workflow_qa_users(role_name text,user_id uuid,sid uuid);
CREATE TEMP TABLE workflow_qa_result(test text,passed boolean);
GRANT SELECT ON workflow_qa_users TO authenticated;
DO $qa$
DECLARE branch integer; r text; u record; staff bigint; oid bigint; denied boolean; second_driver uuid; second_sid uuid:=gen_random_uuid();
BEGIN
 SELECT p.branch_id INTO branch FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id JOIN public.dlv_companies c ON c.id=b.company_id
 WHERE p.active AND b.active AND c.active AND c.onboarding_status='active'
 GROUP BY p.branch_id HAVING bool_or(p.workflow_role='callcenter_followup') AND bool_or(p.workflow_role='kitchen') AND bool_or(p.workflow_role='supervisor') AND bool_or(p.workflow_role='driver') LIMIT 1;
 IF branch IS NULL THEN RAISE EXCEPTION 'Branch with complete workflow roles is missing';END IF;
 FOREACH r IN ARRAY ARRAY['callcenter_followup','kitchen','supervisor','driver'] LOOP
  INSERT INTO workflow_qa_users SELECT r,user_id,gen_random_uuid() FROM public.dlv_profiles WHERE branch_id=branch AND active AND workflow_role=r AND role<>'admin' ORDER BY user_id LIMIT 1;
 END LOOP;
 INSERT INTO auth.sessions(id,user_id,created_at,updated_at) SELECT sid,user_id,now(),now() FROM workflow_qa_users;
 SELECT id INTO staff FROM public.dlv_callcenter_staff WHERE branch_id=branch AND active LIMIT 1;
 IF staff IS NULL THEN INSERT INTO public.dlv_callcenter_staff(branch_id,full_name,active) VALUES(branch,'اختبار معاملة مؤقتة',true) RETURNING id INTO staff;END IF;
 SELECT * INTO u FROM workflow_qa_users WHERE role_name='driver';
 PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';PERFORM public.dlv_set_my_driver_duty('available');EXECUTE 'RESET ROLE';
 SELECT * INTO u FROM workflow_qa_users WHERE role_name='callcenter_followup';
 PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 oid:=public.dlv_create_order('QA-'||left(gen_random_uuid()::text,12),'اختبار معاملة مؤقتة','','','سيتم التراجع عن المعاملة',null,branch,staff);
 denied:=false;BEGIN PERFORM public.dlv_assign_driver(oid,(SELECT user_id FROM workflow_qa_users WHERE role_name='driver'));EXCEPTION WHEN OTHERS THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Call center assigned driver';END IF;
 EXECUTE 'RESET ROLE';
 SELECT * INTO u FROM workflow_qa_users WHERE role_name='kitchen';
 PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';PERFORM public.dlv_kitchen_forward(oid,'اختبار');EXECUTE 'RESET ROLE';
 IF NOT EXISTS(SELECT 1 FROM public.dlv_orders WHERE id=oid AND workflow_stage='kitchen_ready') THEN RAISE EXCEPTION 'Kitchen transition failed';END IF;
 SELECT * INTO u FROM workflow_qa_users WHERE role_name='supervisor';
 PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';PERFORM public.dlv_supervisor_receive(oid,'اختبار');PERFORM public.dlv_assign_driver(oid,(SELECT user_id FROM workflow_qa_users WHERE role_name='driver'),'اختبار');EXECUTE 'RESET ROLE';
 SELECT user_id INTO second_driver FROM public.dlv_profiles WHERE active AND branch_id=branch AND role='driver' AND user_id<>(SELECT user_id FROM workflow_qa_users WHERE role_name='driver') LIMIT 1;
 IF second_driver IS NOT NULL THEN
  INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(second_sid,second_driver,now(),now());
  PERFORM set_config('request.jwt.claim.sub',second_driver::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',second_driver,'session_id',second_sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';denied:=false;BEGIN PERFORM public.dlv_set_status(oid,'received');EXCEPTION WHEN OTHERS THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Other driver received order';END IF;EXECUTE 'RESET ROLE';
 END IF;
 SELECT * INTO u FROM workflow_qa_users WHERE role_name='driver';
 PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 denied:=false;BEGIN PERFORM public.dlv_set_status(oid,'delivered');EXCEPTION WHEN OTHERS THEN denied:=true;END;IF NOT denied THEN RAISE EXCEPTION 'Driver skipped workflow stages';END IF;
 PERFORM public.dlv_set_status(oid,'received');PERFORM public.dlv_set_status(oid,'out');PERFORM public.dlv_set_status(oid,'delivered');EXECUTE 'RESET ROLE';
 IF NOT EXISTS(SELECT 1 FROM public.dlv_orders WHERE id=oid AND status='delivered' AND workflow_stage='delivered' AND received_at IS NOT NULL AND out_at IS NOT NULL AND delivered_at IS NOT NULL) THEN RAISE EXCEPTION 'Delivered state incomplete';END IF;
 INSERT INTO workflow_qa_result VALUES('callcenter_kitchen_supervisor_assignment_driver_delivery',true),('callcenter_assignment_denied',true),('wrong_driver_and_skipped_status_denied',true),('workflow_times_and_final_state_recorded',true);
END $qa$;
SELECT * FROM workflow_qa_result;
ROLLBACK;