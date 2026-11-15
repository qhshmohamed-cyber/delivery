CREATE OR REPLACE FUNCTION public.dlv_submit_public_feedback(p_form uuid,p_request uuid,p_branch integer,p_name text,p_phone text,p_kind text,p_message text,p_order text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f private.dlv_feedback_forms; prior private.dlv_feedback_submissions;
 v_hash text;v_key text;v_hits integer;v_id bigint;v_receipt uuid;v_at timestamptz;
 v_name text:=btrim(coalesce(p_name,''));v_phone text:=regexp_replace(coalesce(p_phone,''),'[ +()-]','','g');
 v_message text:=btrim(coalesce(p_message,''));v_order text:=btrim(coalesce(p_order,''));
BEGIN
 IF p_form IS NULL OR p_request IS NULL OR p_branch IS NULL OR length(v_name) NOT BETWEEN 2 AND 100
 OR v_phone !~ '^[0-9]{8,15}$' OR coalesce(p_kind,'') NOT IN ('complaint','suggestion')
 OR length(v_message) NOT BETWEEN 1 AND 50000 OR length(v_order)>60 THEN
 RETURN jsonb_build_object('success',false,'message','راجع الاسم ورقم الهاتف، واكتب نص الرسالة بما لا يتجاوز 50 ألف حرف');END IF;
 SELECT ff.* INTO f FROM private.dlv_feedback_forms ff JOIN public.dlv_companies c ON c.id=ff.company_id
 JOIN public.dlv_branches b ON b.company_id=c.id AND b.id=p_branch
 WHERE ff.id=p_form AND ff.active AND c.active AND c.onboarding_status='active' AND b.active
 AND (ff.branch_id IS NULL OR ff.branch_id=p_branch) FOR SHARE OF ff,c,b;
 IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','نموذج الشكاوى غير متاح لهذا الفرع');END IF;
 v_hash:=encode(extensions.digest(jsonb_build_array(p_form,p_branch,v_name,v_phone,p_kind,v_message,v_order)::text,'sha256'),'hex');
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text,0));
 SELECT * INTO prior FROM private.dlv_feedback_submissions WHERE request_id=p_request;
 IF FOUND THEN
  IF prior.payload_hash<>v_hash THEN RETURN jsonb_build_object('success',false,'message','طلب الإرسال مختلف. أعد تحميل الصفحة');END IF;
  RETURN jsonb_build_object('success',true,'receipt',prior.receipt,'created_at',prior.created_at,'replayed',true);
 END IF;
 v_key:=private.dlv_public_request_key('feedback');
 DELETE FROM private.dlv_feedback_limits WHERE window_started_at<now()-interval '2 days';
 INSERT INTO private.dlv_feedback_limits(client_key,window_started_at,hits) VALUES(v_key,date_trunc('hour',now()),1)
 ON CONFLICT(client_key) DO UPDATE SET hits=CASE WHEN private.dlv_feedback_limits.window_started_at<date_trunc('hour',now()) THEN 1 ELSE private.dlv_feedback_limits.hits+1 END,window_started_at=date_trunc('hour',now()) RETURNING hits INTO v_hits;
 IF v_hits>(CASE WHEN v_key LIKE '%fallback%' THEN 100 ELSE 10 END) THEN RETURN jsonb_build_object('success',false,'message','وصلت لحد الإرسال مؤقتًا. حاول لاحقًا أو اتصل بالمطعم');END IF;
 INSERT INTO private.dlv_feedback_limits(client_key,window_started_at,hits) VALUES('company:'||f.company_id,date_trunc('hour',now()),1)
 ON CONFLICT(client_key) DO UPDATE SET hits=CASE WHEN private.dlv_feedback_limits.window_started_at<date_trunc('hour',now()) THEN 1 ELSE private.dlv_feedback_limits.hits+1 END,window_started_at=date_trunc('hour',now()) RETURNING hits INTO v_hits;
 IF v_hits>500 THEN RETURN jsonb_build_object('success',false,'message','ضغط مؤقت على خدمة الشكاوى، حاول لاحقًا');END IF;
 INSERT INTO public.dlv_incidents(branch_id,order_id,title,details,priority,status,created_by,category)
 VALUES(p_branch,NULL,CASE WHEN p_kind='suggestion' THEN 'مقترح عميل عبر QR' ELSE 'شكوى عميل عبر QR' END,
 'المصدر: نموذج العميل العام — بيانات تواصل أدخلها العميل ولم يتم التحقق منها' || E'\nالاسم: '||v_name||
 CASE WHEN v_order<>'' THEN E'\nرقم الطلب كما أدخله العميل: '||v_order ELSE '' END||E'\n\n'||v_message,
 'medium','open',NULL,'customer_complaint') RETURNING id,created_at INTO v_id,v_at;
 INSERT INTO private.dlv_feedback_submissions(request_id,form_id,incident_id,payload_hash,customer_name,customer_phone,kind,order_reference,created_at)
 VALUES(p_request,f.id,v_id,v_hash,v_name,v_phone,p_kind,nullif(v_order,''),v_at) RETURNING receipt INTO v_receipt;
 RETURN jsonb_build_object('success',true,'receipt',v_receipt,'created_at',v_at);
END $$;

NOTIFY pgrst,'reload schema';
