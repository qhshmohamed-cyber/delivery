-- Owner command assistant. Structured actions only; no dynamic SQL or external AI calls.
CREATE TABLE private.dlv_owner_assistant_actions(
 request_id uuid PRIMARY KEY,
 actor uuid NOT NULL REFERENCES auth.users(id),
 action text NOT NULL,
 company_id bigint,
 branch_id integer,
 target_user uuid,
 payload jsonb NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.dlv_owner_assistant_actions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.dlv_owner_assistant_actions FROM PUBLIC,anon,authenticated;
CREATE INDEX dlv_owner_assistant_actions_actor_time ON private.dlv_owner_assistant_actions(actor,created_at DESC);

CREATE OR REPLACE FUNCTION public.dlv_owner_assistant_context(p_company_id bigint DEFAULT NULL,p_branch_id integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE branches jsonb:='[]'; employees jsonb:='[]';
BEGIN
 IF NOT public.dlv_session_valid() OR NOT public.dlv_owner_page_check() OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin') THEN RAISE EXCEPTION 'صفحة المالك مقفلة أو الحساب غير مصرح' USING ERRCODE='42501';END IF;
 IF p_company_id IS NULL THEN RETURN jsonb_build_object('branches',branches,'employees',employees);END IF;
 IF NOT EXISTS(SELECT 1 FROM public.dlv_companies WHERE id=p_company_id) THEN RAISE EXCEPTION 'الشركة غير موجودة' USING ERRCODE='22023';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active) ORDER BY name),'[]') INTO branches FROM public.dlv_branches WHERE company_id=p_company_id;
 IF p_branch_id IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.dlv_branches WHERE id=p_branch_id AND company_id=p_company_id) THEN RAISE EXCEPTION 'الفرع لا يتبع الشركة' USING ERRCODE='42501';END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'full_name',full_name,'employee_code',employee_code,'phone',phone,'job_title',job_title,'branch_id',branch_id,'active',active,'version',md5(jsonb_build_array(full_name,employee_code,phone,branch_id)::text)) ORDER BY full_name),'[]')
  INTO employees FROM public.dlv_profiles WHERE branch_id=p_branch_id AND role<>'admin' AND coalesce(workflow_role,'')<>'admin';
 END IF;
 RETURN jsonb_build_object('branches',branches,'employees',employees);
END $$;

CREATE OR REPLACE FUNCTION public.dlv_owner_assistant_history()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF NOT public.dlv_session_valid() OR NOT public.dlv_owner_page_check() OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin') THEN RAISE EXCEPTION 'غير مصرح' USING ERRCODE='42501';END IF;
 RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x.created_at DESC),'[]') FROM (SELECT request_id,action,company_id,branch_id,created_at,result FROM private.dlv_owner_assistant_actions WHERE actor=auth.uid() ORDER BY created_at DESC LIMIT 30)x);
END $$;

CREATE OR REPLACE FUNCTION public.dlv_owner_assistant_execute(
 p_request_id uuid,p_action text,p_company_id bigint DEFAULT NULL,p_branch_id integer DEFAULT NULL,p_user uuid DEFAULT NULL,p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE cached private.dlv_owner_assistant_actions; cid bigint:=p_company_id; bid integer:=p_branch_id; output jsonb; allowed text[]; clean text; first_branch text; logo text; employee public.dlv_profiles; label text; canonical jsonb;
BEGIN
 IF NOT public.dlv_session_valid() OR NOT public.dlv_owner_page_check() OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin') THEN RAISE EXCEPTION 'صفحة المالك مقفلة أو الحساب غير مصرح' USING ERRCODE='42501';END IF;
 IF p_request_id IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR octet_length(p_data::text)>12000 THEN RAISE EXCEPTION 'طلب غير صالح' USING ERRCODE='22023';END IF;
 allowed:=CASE p_action WHEN 'create_company' THEN ARRAY['name','logo_url','first_branch'] WHEN 'add_branch' THEN ARRAY['name'] WHEN 'rename_branch' THEN ARRAY['name','expected_name'] WHEN 'update_employee' THEN ARRAY['full_name','employee_code','phone','version'] ELSE NULL END;
 IF allowed IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_data)k WHERE NOT(k=ANY(allowed))) THEN RAISE EXCEPTION 'عملية أو حقل غير مدعوم' USING ERRCODE='22023';END IF;
 canonical:=jsonb_build_object('company_id',p_company_id,'branch_id',p_branch_id,'user_id',p_user,'data',p_data);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('owner-assistant-'||p_request_id::text,0));
 SELECT * INTO cached FROM private.dlv_owner_assistant_actions WHERE request_id=p_request_id;
 IF FOUND THEN
  IF cached.actor<>auth.uid() OR cached.action<>p_action OR cached.payload<>canonical THEN RAISE EXCEPTION 'معرّف عملية مستخدم بطلب مختلف' USING ERRCODE='22023';END IF;
  RETURN cached.result;
 END IF;
 IF p_action='create_company' THEN
  IF p_company_id IS NOT NULL OR p_branch_id IS NOT NULL OR p_user IS NOT NULL THEN RAISE EXCEPTION 'نطاق إنشاء الشركة غير صالح' USING ERRCODE='22023';END IF;
  clean:=regexp_replace(btrim(coalesce(p_data->>'name','')),'\s+',' ','g');
  first_branch:=regexp_replace(btrim(coalesce(nullif(p_data->>'first_branch',''),'الفرع الرئيسي')),'\s+',' ','g');
  logo:=nullif(p_data->>'logo_url','');
  IF length(clean) NOT BETWEEN 2 AND 120 OR length(first_branch) NOT BETWEEN 3 AND 100 THEN RAISE EXCEPTION 'راجع اسم الشركة والفرع الأول' USING ERRCODE='22023';END IF;
  IF logo IS NOT NULL AND (length(logo)>1000 OR logo !~ '^https://mkptmejkcemdhlhdaort\.supabase\.co/storage/v1/object/public/brand-assets/assistant-logos/[a-f0-9-]+\.(png|jpg|webp)$') THEN RAISE EXCEPTION 'ارفع اللوجو من المساعد أولاً' USING ERRCODE='22023';END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('assistant-company-'||lower(clean),0));
  IF EXISTS(SELECT 1 FROM public.dlv_companies WHERE lower(btrim(name))=lower(clean)) THEN RAISE EXCEPTION 'الشركة موجودة بالفعل؛ اخترها من القائمة' USING ERRCODE='23505';END IF;
  cid:=public.dlv_owner_register_company(clean,'company-'||replace(gen_random_uuid()::text,'-',''));
  INSERT INTO public.dlv_company_branding(company_id,brand_name,logo_url,background_url,bg_color,card_color,brand_color,gold_color)
  VALUES(cid,clean,logo,logo,'#101827','#172235','#a77d3e','#c69b53')
  ON CONFLICT(company_id) DO UPDATE SET brand_name=excluded.brand_name,logo_url=excluded.logo_url,background_url=excluded.background_url,bg_color=excluded.bg_color,card_color=excluded.card_color,brand_color=excluded.brand_color,gold_color=excluded.gold_color,updated_at=now();
  bid:=public.dlv_owner_add_company_branch(cid,first_branch);
  label:='تم إنشاء شركة '||clean||' وفرع '||first_branch||'. التشغيل بانتظار فحص العزل الأمني.';
  output:=jsonb_build_object('company_id',cid,'branch_id',bid,'company_name',clean,'summary',label,'onboarding_status','pending_isolation');
 ELSE
  IF p_company_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.dlv_companies WHERE id=p_company_id) THEN RAISE EXCEPTION 'اختر الشركة الصحيحة' USING ERRCODE='22023';END IF;
  IF p_action='add_branch' THEN
   IF p_branch_id IS NOT NULL OR p_user IS NOT NULL THEN RAISE EXCEPTION 'نطاق إضافة الفرع غير صالح' USING ERRCODE='22023';END IF;
   bid:=public.dlv_owner_add_company_branch(cid,p_data->>'name');
   label:='تمت إضافة فرع '||(p_data->>'name');
   output:=jsonb_build_object('company_id',cid,'branch_id',bid,'summary',label);
  ELSE
   IF NOT EXISTS(SELECT 1 FROM public.dlv_branches WHERE id=p_branch_id AND company_id=p_company_id) THEN RAISE EXCEPTION 'الفرع لا يتبع الشركة المحددة' USING ERRCODE='42501';END IF;
   IF p_action='rename_branch' THEN
    IF p_user IS NOT NULL THEN RAISE EXCEPTION 'نطاق تعديل الفرع غير صالح' USING ERRCODE='22023';END IF;
    SELECT name INTO clean FROM public.dlv_branches WHERE id=p_branch_id AND company_id=p_company_id FOR UPDATE;
    IF clean IS DISTINCT FROM p_data->>'expected_name' THEN RAISE EXCEPTION 'اسم الفرع تغير بعد المعاينة. أعد تحميل النطاق.' USING ERRCODE='40001';END IF;
    output:=public.dlv_owner_rename_company_branch(cid,bid,p_data->>'name');
    label:='تم تغيير اسم الفرع من '||clean||' إلى '||(output->>'name');
    output:=output||jsonb_build_object('summary',label);
   ELSIF p_action='update_employee' THEN
    SELECT * INTO employee FROM public.dlv_profiles WHERE user_id=p_user AND branch_id=p_branch_id AND role<>'admin' AND coalesce(workflow_role,'')<>'admin' FOR UPDATE;
    IF NOT FOUND OR p_user=auth.uid() THEN RAISE EXCEPTION 'الحساب غير مطابق للشركة والفرع أو غير قابل للتعديل هنا' USING ERRCODE='42501';END IF;
    IF md5(jsonb_build_array(employee.full_name,employee.employee_code,employee.phone,employee.branch_id)::text) IS DISTINCT FROM p_data->>'version' THEN RAISE EXCEPTION 'الحساب تغير بعد المعاينة. أعد تحميله.' USING ERRCODE='40001';END IF;
    IF length(btrim(coalesce(p_data->>'full_name',''))) NOT BETWEEN 2 AND 120 OR length(btrim(coalesce(p_data->>'employee_code',''))) NOT BETWEEN 1 AND 40 OR coalesce(p_data->>'phone','') !~ '^[+0-9 ()-]{0,25}$' THEN RAISE EXCEPTION 'راجع الاسم والكود ورقم الموبايل' USING ERRCODE='22023';END IF;
    PERFORM public.dlv_update_pilot(p_user,p_data->>'full_name',p_data->>'employee_code');
    PERFORM public.dlv_set_pilot_phone(p_user,p_data->>'phone');
    label:='تم تعديل بيانات حساب '||(p_data->>'full_name');
    output:=jsonb_build_object('company_id',cid,'branch_id',bid,'user_id',p_user,'summary',label);
   END IF;
  END IF;
 END IF;
 output:=output||jsonb_build_object('request_id',p_request_id,'action',p_action);
 INSERT INTO private.dlv_owner_assistant_actions(request_id,actor,action,company_id,branch_id,target_user,payload,result) VALUES(p_request_id,auth.uid(),p_action,cid,bid,p_user,canonical,output);
 INSERT INTO public.dlv_security_audit(actor,branch_id,entity,entity_id,action,changes)
 VALUES(auth.uid(),bid,'dlv_owner_assistant',p_request_id::text,'EXECUTE',jsonb_build_object('assistant_action',p_action,'company_id',cid,'target_user',p_user));
 RETURN output;
END $$;
REVOKE ALL ON FUNCTION public.dlv_owner_assistant_context(bigint,integer),public.dlv_owner_assistant_history(),public.dlv_owner_assistant_execute(uuid,text,bigint,integer,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_owner_assistant_context(bigint,integer),public.dlv_owner_assistant_history(),public.dlv_owner_assistant_execute(uuid,text,bigint,integer,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';


-- Logo writes require a live, unlocked owner session.
ALTER POLICY brand_assets_owner_insert ON storage.objects WITH CHECK (
 bucket_id='brand-assets' AND public.dlv_session_valid() AND public.dlv_owner_page_check()
 AND EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin')
);
ALTER POLICY brand_assets_owner_update ON storage.objects USING (
 bucket_id='brand-assets' AND public.dlv_session_valid() AND public.dlv_owner_page_check()
 AND EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin')
) WITH CHECK (
 bucket_id='brand-assets' AND public.dlv_session_valid() AND public.dlv_owner_page_check()
 AND EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin')
);