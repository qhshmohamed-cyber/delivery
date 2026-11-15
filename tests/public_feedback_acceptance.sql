BEGIN;
SELECT set_config('test.feedback_form',(SELECT id::text FROM private.dlv_feedback_forms WHERE company_id=(SELECT id FROM public.dlv_companies WHERE slug='wahat-al-yemen') AND branch_id IS NULL),true);
SELECT set_config('test.feedback_branch',(SELECT min(b.id)::text FROM public.dlv_branches b JOIN public.dlv_companies c ON c.id=b.company_id WHERE c.slug='wahat-al-yemen' AND b.active),true);
SELECT set_config('test.other_branch',(SELECT min(b.id)::text FROM public.dlv_branches b JOIN public.dlv_companies c ON c.id=b.company_id WHERE c.slug<>'wahat-al-yemen' AND b.active),true);
SELECT set_config('test.feedback_request',gen_random_uuid()::text,true);
SET LOCAL ROLE anon;
DO $$
DECLARE f uuid:=current_setting('test.feedback_form')::uuid;b integer:=current_setting('test.feedback_branch')::integer;r uuid:=current_setting('test.feedback_request')::uuid;j jsonb;k jsonb;
BEGIN
 IF has_table_privilege('anon','public.dlv_incidents','INSERT') OR has_schema_privilege('anon','private','USAGE') THEN RAISE EXCEPTION 'Unexpected public table permissions';END IF;
 j:=public.dlv_feedback_config(f);
 IF NOT (j->>'available')::boolean OR j->>'company_name'<>'واحة اليمن' THEN RAISE EXCEPTION 'Wrong public company branding';END IF;
 j:=public.dlv_submit_public_feedback(f,r,b,'اختبار قبول مؤقت','01000000000','complaint','رسالة اختبار قبول فني مؤقتة لا تخص عميلًا حقيقيًا','TEST-ROLLBACK');
 IF j->>'success'<>'true' OR j->>'receipt' IS NULL OR j->>'created_at' IS NULL THEN RAISE EXCEPTION 'Submission failed: %',j;END IF;
 k:=public.dlv_submit_public_feedback(f,r,b,'اختبار قبول مؤقت','01000000000','complaint','رسالة اختبار قبول فني مؤقتة لا تخص عميلًا حقيقيًا','TEST-ROLLBACK');
 IF k->>'receipt'<>j->>'receipt' OR k->>'replayed'<>'true' THEN RAISE EXCEPTION 'Idempotency failed';END IF;
 k:=public.dlv_submit_public_feedback(f,r,current_setting('test.other_branch')::integer,'اختبار قبول مؤقت','01000000000','complaint','رسالة اختبار قبول فني مؤقتة لا تخص عميلًا حقيقيًا',NULL);
 IF k->>'success'='true' THEN RAISE EXCEPTION 'Cross-company routing allowed';END IF;
 k:=public.dlv_submit_public_feedback(f,gen_random_uuid(),b,'اختبار','01000000000','complaint','قصير',NULL);
 IF k->>'success'='true' THEN RAISE EXCEPTION 'Invalid message accepted';END IF;
 BEGIN PERFORM public.dlv_owner_feedback_form(1,NULL);RAISE EXCEPTION 'Public can create forms';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$
DECLARE v_id bigint;v_branch integer:=current_setting('test.feedback_branch')::integer;v_user uuid;v_sid uuid;v_count integer;
BEGIN
 SELECT s.incident_id INTO STRICT v_id FROM private.dlv_feedback_submissions s JOIN public.dlv_incidents i ON i.id=s.incident_id
 WHERE s.request_id=current_setting('test.feedback_request')::uuid AND i.branch_id=v_branch AND i.created_by IS NULL AND i.category='customer_complaint' AND i.created_at=now();
 SELECT p.user_id,s.id INTO v_user,v_sid FROM public.dlv_profiles p JOIN auth.sessions s ON s.user_id=p.user_id JOIN auth.users u ON u.id=p.user_id
 WHERE p.active AND p.workflow_role='complaints_officer' AND p.branch_id=v_branch AND (s.not_after IS NULL OR s.not_after>now()) AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now()) LIMIT 1;
 IF v_user IS NULL THEN
  SELECT p.user_id INTO v_user FROM public.dlv_profiles p JOIN auth.users u ON u.id=p.user_id WHERE p.active AND p.workflow_role='complaints_officer' AND p.branch_id=v_branch AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now()) LIMIT 1;
  IF v_user IS NULL THEN RAISE EXCEPTION 'No active complaint-officer account to verify inbox';END IF;
  v_sid:=gen_random_uuid();
  INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(v_sid,v_user,now(),now());
 END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'session_id',v_sid,'role','authenticated','exp',extract(epoch from now()+interval '5 minutes')::bigint)::text,true);
 SELECT count(*) INTO v_count FROM public.dlv_complaint_inbox(v_branch) WHERE id=v_id AND customer_phone='01000000000' AND order_no='TEST-ROLLBACK';
 IF v_count<>1 THEN RAISE EXCEPTION 'Complaint not visible in authorized officer inbox';END IF;
 IF public.dlv_complaint_whatsapp_context(v_id)->>'company'<>'واحة اليمن' OR public.dlv_complaint_whatsapp_context(v_id)->>'phone'<>'01000000000' OR public.dlv_complaint_whatsapp_context(v_id)->>'officer' IS NULL THEN RAISE EXCEPTION 'Wrong WhatsApp sender or company';END IF;
 BEGIN PERFORM public.dlv_complaint_inbox(current_setting('test.other_branch')::integer);RAISE EXCEPTION 'Cross-company inbox allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM public.dlv_complaint_followup(v_id,'إجراء قبول فني مؤقت سيتم التراجع عنه','resolved');
 IF NOT EXISTS(SELECT 1 FROM public.dlv_incidents WHERE id=v_id AND status='resolved' AND followup_by=v_user) THEN RAISE EXCEPTION 'Followup did not save';END IF;
 BEGIN PERFORM public.dlv_owner_feedback_form(1,NULL);RAISE EXCEPTION 'Officer created owner-only QR';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE public.dlv_companies SET active=false WHERE slug='wahat-al-yemen';
 IF public.dlv_feedback_config(current_setting('test.feedback_form')::uuid)->>'available'<>'false' THEN RAISE EXCEPTION 'Suspended company form remains available';END IF;
 IF public.dlv_submit_public_feedback(current_setting('test.feedback_form')::uuid,gen_random_uuid(),v_branch,'اختبار','01000000000','complaint','اختبار عدم استقبال شكاوى الشركة المعلقة',NULL)->>'success'='true' THEN RAISE EXCEPTION 'Suspended company accepted submission';END IF;
END $$;
ROLLBACK;
SELECT 'PASS: anonymous submission, branding, timestamps, idempotency, branch isolation, officer inbox, followup; all test data rolled back' AS acceptance;
