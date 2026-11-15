-- Customer submissions are write-only. Routing is resolved server-side from an opaque form ID.
CREATE TABLE private.dlv_feedback_forms (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id bigint NOT NULL REFERENCES public.dlv_companies(id),
 branch_id integer REFERENCES public.dlv_branches(id),
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE NULLS NOT DISTINCT(company_id,branch_id)
);
CREATE TABLE private.dlv_feedback_submissions (
 request_id uuid PRIMARY KEY,
 form_id uuid NOT NULL REFERENCES private.dlv_feedback_forms(id),
 incident_id bigint NOT NULL UNIQUE REFERENCES public.dlv_incidents(id),
 receipt uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 payload_hash text NOT NULL,
 customer_name text NOT NULL,
 customer_phone text NOT NULL,
 kind text NOT NULL CHECK(kind IN ('complaint','suggestion')),
 order_reference text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private.dlv_feedback_limits (
 client_key text PRIMARY KEY, window_started_at timestamptz NOT NULL, hits integer NOT NULL
);
ALTER TABLE private.dlv_feedback_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.dlv_feedback_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.dlv_feedback_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.dlv_feedback_forms,private.dlv_feedback_submissions,private.dlv_feedback_limits FROM PUBLIC,anon,authenticated;
-- Public customer messages have no employee author; never impersonate an employee.
ALTER TABLE public.dlv_incidents ALTER COLUMN created_by DROP NOT NULL;

CREATE FUNCTION public.dlv_feedback_config(p_form uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce((SELECT jsonb_build_object('available',true,'company_name',c.name,
 'branch_id',f.branch_id,'logo_url',coalesce(br.logo_url,''),
 'brand_color',coalesce(br.brand_color,'#5a3317'),'gold_color',coalesce(br.gold_color,'#b9832e'),
 'branches',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name) ORDER BY b.id),'[]'::jsonb)
 FROM public.dlv_branches b WHERE b.company_id=c.id AND b.active AND (f.branch_id IS NULL OR b.id=f.branch_id)))
 FROM private.dlv_feedback_forms f JOIN public.dlv_companies c ON c.id=f.company_id
 LEFT JOIN public.dlv_company_branding br ON br.company_id=c.id
 WHERE f.id=p_form AND f.active AND c.active AND c.onboarding_status='active'
 AND EXISTS(SELECT 1 FROM public.dlv_branches b WHERE b.company_id=c.id AND b.active AND (f.branch_id IS NULL OR b.id=f.branch_id))),
 jsonb_build_object('available',false));
$$;
REVOKE ALL ON FUNCTION public.dlv_feedback_config(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dlv_feedback_config(uuid) TO anon,authenticated;

CREATE FUNCTION public.dlv_owner_feedback_form(p_company bigint,p_branch integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f private.dlv_feedback_forms;
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS DISTINCT FROM 'admin' OR NOT public.dlv_owner_page_check() THEN
 RAISE EXCEPTION 'حساب المالك والتحقق من قفل صفحته مطلوبان' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.dlv_companies WHERE id=p_company) OR
 (p_branch IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.dlv_branches WHERE id=p_branch AND company_id=p_company)) THEN
 RAISE EXCEPTION 'الشركة أو الفرع غير مطابق' USING ERRCODE='22023'; END IF;
 INSERT INTO private.dlv_feedback_forms(company_id,branch_id) VALUES(p_company,p_branch)
 ON CONFLICT(company_id,branch_id) DO NOTHING;
 SELECT * INTO STRICT f FROM private.dlv_feedback_forms WHERE company_id=p_company AND branch_id IS NOT DISTINCT FROM p_branch;
 RETURN jsonb_build_object('form_id',f.id,'company_id',f.company_id,'branch_id',f.branch_id);
END $$;
REVOKE ALL ON FUNCTION public.dlv_owner_feedback_form(bigint,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_owner_feedback_form(bigint,integer) TO authenticated;

CREATE FUNCTION public.dlv_submit_public_feedback(p_form uuid,p_request uuid,p_branch integer,p_name text,p_phone text,p_kind text,p_message text,p_order text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f private.dlv_feedback_forms; prior private.dlv_feedback_submissions;
 v_hash text;v_key text;v_hits integer;v_id bigint;v_receipt uuid;v_at timestamptz;
 v_name text:=btrim(coalesce(p_name,''));v_phone text:=regexp_replace(coalesce(p_phone,''),'[ +()-]','','g');
 v_message text:=btrim(coalesce(p_message,''));v_order text:=btrim(coalesce(p_order,''));
BEGIN
 IF p_form IS NULL OR p_request IS NULL OR p_branch IS NULL OR length(v_name) NOT BETWEEN 2 AND 100
 OR v_phone !~ '^[0-9]{8,15}$' OR coalesce(p_kind,'') NOT IN ('complaint','suggestion')
 OR length(v_message) NOT BETWEEN 10 AND 2000 OR length(v_order)>60 THEN
 RETURN jsonb_build_object('success',false,'message','راجع الاسم ورقم الهاتف ونص الرسالة (10 أحرف على الأقل)');END IF;
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
REVOKE ALL ON FUNCTION public.dlv_submit_public_feedback(uuid,uuid,integer,text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dlv_submit_public_feedback(uuid,uuid,integer,text,text,text,text,text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.dlv_complaint_inbox(p_branch integer DEFAULT NULL)
RETURNS TABLE(id bigint,branch_id integer,order_no text,customer_phone text,title text,details text,priority text,status text,created_at timestamptz,updated_at timestamptz,followup_action text,followup_at timestamptz,followup_employee text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_role text:=public.dlv_role();
BEGIN
 IF NOT public.dlv_session_valid() OR v_role IS NULL OR auth.uid() IS NULL OR v_role NOT IN ('admin','manager','complaints_officer') THEN RAISE EXCEPTION 'غير مصرح' USING ERRCODE='42501';END IF;
 IF v_role='admin' AND NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'تحقق المالك مطلوب' USING ERRCODE='42501';END IF;
 IF p_branch IS NOT NULL AND NOT public.dlv_can_access_branch(p_branch) THEN RAISE EXCEPTION 'فرع غير مصرح' USING ERRCODE='42501';END IF;
 RETURN QUERY SELECT i.id,i.branch_id,coalesce(o.order_no,s.order_reference),coalesce(s.customer_phone,o.phone),i.title,i.details,i.priority,i.status,i.created_at,i.updated_at,i.followup_action,i.followup_at,p.full_name
 FROM public.dlv_incidents i LEFT JOIN public.dlv_orders o ON o.id=i.order_id AND o.branch_id=i.branch_id
 LEFT JOIN private.dlv_feedback_submissions s ON s.incident_id=i.id LEFT JOIN public.dlv_profiles p ON p.user_id=i.followup_by
 WHERE i.category='customer_complaint' AND (p_branch IS NULL OR i.branch_id=p_branch)
 AND public.dlv_can_access_branch(i.branch_id) ORDER BY i.created_at DESC,i.id DESC LIMIT 300;
END $$;
REVOKE ALL ON FUNCTION public.dlv_complaint_inbox(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_complaint_inbox(integer) TO authenticated;

INSERT INTO private.dlv_feedback_forms(company_id,branch_id)
SELECT id,NULL FROM public.dlv_companies WHERE slug='wahat-al-yemen'
ON CONFLICT(company_id,branch_id) DO NOTHING;
NOTIFY pgrst,'reload schema';
