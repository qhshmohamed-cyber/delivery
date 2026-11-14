CREATE OR REPLACE FUNCTION public.dlv_create_customer_complaint(p_order_id bigint, p_title text, p_details text, p_priority text DEFAULT 'medium'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare o public.dlv_orders; v_id bigint; v_role text:=public.dlv_role();
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS NULL THEN RAISE EXCEPTION 'Session invalid or account unavailable' USING ERRCODE='42501'; END IF;
 IF public.dlv_role()='admin' AND NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Owner verification required' USING ERRCODE='42501'; END IF;

 if auth.uid() is null or v_role not in ('admin','manager','callcenter_followup','complaints_officer') then raise exception 'غير مصرح'; end if;
 select * into o from public.dlv_orders where id=p_order_id;
 if not found or not public.dlv_can_access_branch(o.branch_id) then raise exception 'الطلب غير متاح'; end if;
 if length(trim(coalesce(p_title,''))) not between 3 and 160 or length(coalesce(p_details,''))>2000 or p_priority not in ('low','medium','high','critical') then raise exception 'بيانات الشكوى غير صحيحة'; end if;
 insert into public.dlv_incidents(branch_id,order_id,title,details,priority,status,created_by,category)
 values(o.branch_id,o.id,trim(p_title),coalesce(p_details,''),p_priority,'open',auth.uid(),'customer_complaint') returning id into v_id;
 insert into public.dlv_security_audit(actor,branch_id,entity,entity_id,action,changes)
 values(auth.uid(),o.branch_id,'dlv_incidents',v_id::text,'COMPLAINT_CREATED',jsonb_build_object('order_id',o.id,'priority',p_priority));
 return jsonb_build_object('success',true,'id',v_id);
end $function$
;
CREATE TABLE private.dlv_complaint_requests (
 request_id uuid PRIMARY KEY, actor uuid NOT NULL, payload_hash text NOT NULL, incident_id bigint NOT NULL REFERENCES public.dlv_incidents(id), created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.dlv_complaint_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.dlv_complaint_requests FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.dlv_register_complaint_by_order(p_request uuid,p_branch integer,p_day date,p_order_no text,p_title text,p_details text,p_priority text,p_status text,p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_ids bigint[];v_result jsonb;v_id bigint;v_hash text;v_previous private.dlv_complaint_requests;
BEGIN
 IF NOT public.dlv_session_valid() OR coalesce(public.dlv_role(),'') NOT IN ('admin','manager','complaints_officer') OR NOT public.dlv_can_access_branch(p_branch) THEN RAISE EXCEPTION 'غير مصرح بتسجيل الشكوى لهذا الفرع' USING ERRCODE='42501';END IF;
 IF p_request IS NULL OR p_day IS NULL OR p_day>public.dlv_operational_day(now()) OR length(trim(coalesce(p_order_no,''))) NOT BETWEEN 1 AND 60 OR coalesce(p_status,'') NOT IN ('open','in_progress','resolved') OR length(trim(coalesce(p_action,''))) NOT BETWEEN 3 AND 1500 THEN RAISE EXCEPTION 'حدد رقم الطلب وتاريخه واكتب الإجراء وطريقة الحل بوضوح' USING ERRCODE='22023';END IF;
 v_hash:=encode(extensions.digest(jsonb_build_array(p_branch,p_day,trim(p_order_no),p_title,p_details,p_priority,p_status,p_action)::text,'sha256'),'hex');
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request::text,0));
 SELECT * INTO v_previous FROM private.dlv_complaint_requests WHERE request_id=p_request;
 IF FOUND THEN
  IF v_previous.actor<>auth.uid() OR v_previous.payload_hash<>v_hash THEN RAISE EXCEPTION 'طلب حفظ غير متطابق' USING ERRCODE='22023';END IF;
  RETURN jsonb_build_object('success',true,'id',v_previous.incident_id,'replayed',true);
 END IF;
 SELECT array_agg(o.id) INTO v_ids FROM public.dlv_orders o WHERE o.branch_id=p_branch AND o.order_date=p_day AND o.order_no=trim(p_order_no);
 IF coalesce(cardinality(v_ids),0)=0 THEN RAISE EXCEPTION 'لا يوجد طلب بهذا الرقم في الفرع وتاريخ الطلب المحددين' USING ERRCODE='22023';END IF;
 IF cardinality(v_ids)<>1 THEN RAISE EXCEPTION 'يوجد أكثر من طلب مطابق؛ راجع رقم الطلب مع الإدارة' USING ERRCODE='22023';END IF;
 v_result:=public.dlv_create_customer_complaint(v_ids[1],p_title,p_details,p_priority);
 v_id:=(v_result->>'id')::bigint;
 PERFORM public.dlv_complaint_followup(v_id,trim(p_action),p_status);
 INSERT INTO private.dlv_complaint_requests(request_id,actor,payload_hash,incident_id) VALUES(p_request,auth.uid(),v_hash,v_id);
 RETURN jsonb_build_object('success',true,'id',v_id);
END $$;
REVOKE ALL ON FUNCTION public.dlv_register_complaint_by_order(uuid,integer,date,text,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_register_complaint_by_order(uuid,integer,date,text,text,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.dlv_daily_complaint_summary(p_branch integer,p_day date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_start timestamptz;v_end timestamptz;v_items jsonb;v_actions jsonb;
BEGIN
 IF NOT public.dlv_session_valid() OR NOT public.dlv_can_access_branch(p_branch)
 OR NOT ((public.dlv_role()='admin' AND public.dlv_owner_page_check()) OR
 EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='manager' AND workflow_role='manager' AND branch_id=p_branch)) THEN RAISE EXCEPTION 'غير مصرح بتقرير الشكاوى' USING ERRCODE='42501';END IF;
 IF p_day IS NULL OR p_day>public.dlv_operational_day(now()) THEN RAISE EXCEPTION 'تاريخ التقرير غير صحيح' USING ERRCODE='22023';END IF;
 v_start:=(p_day::timestamp+interval '5 hours') AT TIME ZONE 'Africa/Cairo';
 v_end:=((p_day+1)::timestamp+interval '5 hours') AT TIME ZONE 'Africa/Cairo';
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.id,'order_no',o.order_no,'order_day',o.order_date,'title',i.title,'details',i.details,'priority',i.priority,'status',i.status,'created_at',i.created_at,'created_by',coalesce(cr.full_name,'غير محدد'),'action',i.followup_action,'officer',coalesce(fp.full_name,'غير محدد'),'followup_at',i.followup_at,'resolved_at',i.resolved_at) ORDER BY i.created_at,i.id),'[]'::jsonb)
 INTO v_items FROM public.dlv_incidents i LEFT JOIN public.dlv_orders o ON o.id=i.order_id AND o.branch_id=i.branch_id LEFT JOIN public.dlv_profiles cr ON cr.user_id=i.created_by LEFT JOIN public.dlv_profiles fp ON fp.user_id=i.followup_by
 WHERE i.branch_id=p_branch AND i.category='customer_complaint' AND i.created_at>=v_start AND i.created_at<v_end;
 SELECT coalesce(jsonb_agg(jsonb_build_object('complaint_id',i.id,'order_no',o.order_no,'title',i.title,'action',a.action_text,'status',a.status_after,'officer',coalesce(p.full_name,'غير محدد'),'at',a.created_at) ORDER BY a.created_at,a.id),'[]'::jsonb)
 INTO v_actions FROM public.dlv_complaint_actions a JOIN public.dlv_incidents i ON i.id=a.incident_id LEFT JOIN public.dlv_orders o ON o.id=i.order_id AND o.branch_id=i.branch_id LEFT JOIN public.dlv_profiles p ON p.user_id=a.actor
 WHERE i.branch_id=p_branch AND i.category='customer_complaint' AND a.created_at>=v_start AND a.created_at<v_end;
 RETURN jsonb_build_object('branch_id',p_branch,'day',p_day,'items',v_items,'actions',v_actions,'as_of',now());
END $$;
REVOKE ALL ON FUNCTION public.dlv_daily_complaint_summary(integer,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_daily_complaint_summary(integer,date) TO authenticated;

CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;

-- Free HIBP range checks for application-managed account creation and password changes.
-- No plaintext or complete password digest is sent externally or stored.
CREATE OR REPLACE FUNCTION private.dlv_checked_password_hash(p_password text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_digest text;v_response extensions.http_response;v_line text;v_lines integer:=0;
BEGIN
 IF p_password IS NULL OR octet_length(p_password)>72 OR length(p_password)<12 OR p_password!~'[A-Z]' OR p_password!~'[a-z]' OR p_password!~'[0-9]' OR p_password!~'[^A-Za-z0-9]' THEN RAISE EXCEPTION 'كلمة المرور تحتاج 12 حرفًا على الأقل: حرف كبير وصغير ورقم ورمز، وبحد أقصى 72 بايت' USING ERRCODE='22023';END IF;
 v_digest:=upper(encode(extensions.digest(p_password,'sha1'),'hex'));
 BEGIN
  PERFORM set_config('http.curlopt_timeout_ms','4000',true);
  PERFORM set_config('http.curlopt_connecttimeout_ms','1500',true);
  PERFORM set_config('http.curlopt_ssl_verifypeer','1',true);
  PERFORM set_config('http.curlopt_ssl_verifyhost','2',true);
  SELECT * INTO v_response FROM extensions.http(('GET','https://api.pwnedpasswords.com/range/'||left(v_digest,5),ARRAY[extensions.http_header('Add-Padding','true'),extensions.http_header('User-Agent','YourStaff-PasswordGuard/1.0 (+https://qhshmohamed-cyber.github.io/delivery/)')],NULL,NULL)::extensions.http_request);
 EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'تعذر فحص تسريب كلمة المرور الآن. لم يتم حفظ تغيير؛ حاول مجددًا بعد قليل' USING ERRCODE='58000';
 END;
 IF v_response.status<>200 OR octet_length(v_response.content) NOT BETWEEN 1000 AND 500000 THEN RAISE EXCEPTION 'خدمة فحص كلمة المرور غير متاحة. لم يتم حفظ تغيير' USING ERRCODE='58000';END IF;
 FOR v_line IN SELECT regexp_split_to_table(v_response.content,E'\n') LOOP
  v_line:=btrim(v_line,E'\r\n ');
  IF v_line='' THEN CONTINUE;END IF;
  IF v_line!~'^[A-F0-9]{35}:[0-9]{1,15}$' THEN RAISE EXCEPTION 'استجابة فحص كلمة المرور غير صالحة. لم يتم حفظ تغيير' USING ERRCODE='58000';END IF;
  v_lines:=v_lines+1;
  IF split_part(v_line,':',1)=substring(v_digest from 6) AND split_part(v_line,':',2)::bigint>0 THEN RAISE EXCEPTION 'كلمة المرور ظهرت في تسريب سابق. اختر كلمة مرور فريدة مختلفة' USING ERRCODE='22023';END IF;
 END LOOP;
 IF v_lines<100 THEN RAISE EXCEPTION 'فحص كلمة المرور غير مكتمل. لم يتم حفظ تغيير' USING ERRCODE='58000';END IF;
 RETURN extensions.crypt(p_password,extensions.gen_salt('bf',12));
END $$;
REVOKE ALL ON FUNCTION private.dlv_checked_password_hash(text) FROM PUBLIC,anon,authenticated;
DO $permissions$
DECLARE f record;
BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_depend d ON d.objid=p.oid AND d.classid='pg_proc'::regclass JOIN pg_extension e ON e.oid=d.refobjid WHERE e.extname='http' AND d.deptype='e' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.signature);
 END LOOP;
END $permissions$;
CREATE TABLE private.dlv_password_attempts(user_id uuid PRIMARY KEY,attempts integer NOT NULL DEFAULT 0,blocked_until timestamptz);
ALTER TABLE private.dlv_password_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.dlv_password_attempts FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.dlv_owner_change_login_password(p_current text,p_new text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_old text;v_new text;v_attempt private.dlv_password_attempts;v_sid uuid:=(auth.jwt()->>'session_id')::uuid;
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS DISTINCT FROM 'admin' OR NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'مالك النظام بعد فتح حماية الصفحة فقط' USING ERRCODE='42501';END IF;
 INSERT INTO private.dlv_password_attempts(user_id) VALUES(auth.uid()) ON CONFLICT DO NOTHING;
 SELECT * INTO v_attempt FROM private.dlv_password_attempts WHERE user_id=auth.uid() FOR UPDATE;
 IF v_attempt.blocked_until>now() THEN RETURN jsonb_build_object('success',false,'message','تم إيقاف المحاولات مؤقتًا. حاول بعد 15 دقيقة');END IF;
 IF v_attempt.blocked_until IS NOT NULL THEN UPDATE private.dlv_password_attempts SET attempts=0,blocked_until=NULL WHERE user_id=auth.uid();v_attempt.attempts:=0;END IF;
 SELECT encrypted_password INTO v_old FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 IF p_current IS NULL OR octet_length(p_current)>72 OR v_old IS NULL OR extensions.crypt(p_current,v_old) IS DISTINCT FROM v_old THEN
  UPDATE private.dlv_password_attempts SET attempts=v_attempt.attempts+1,blocked_until=CASE WHEN v_attempt.attempts+1>=5 THEN now()+interval '15 minutes' ELSE NULL END WHERE user_id=auth.uid();
  RETURN jsonb_build_object('success',false,'message','كلمة المرور الحالية غير صحيحة');
 END IF;
 IF p_current=p_new THEN RAISE EXCEPTION 'اختر كلمة مرور مختلفة عن الحالية' USING ERRCODE='22023';END IF;
 v_new:=private.dlv_checked_password_hash(p_new);
 UPDATE auth.users SET encrypted_password=v_new,updated_at=now() WHERE id=auth.uid();
 DELETE FROM auth.refresh_tokens WHERE user_id=auth.uid()::text AND session_id IS DISTINCT FROM v_sid;
 DELETE FROM auth.sessions WHERE user_id=auth.uid() AND id IS DISTINCT FROM v_sid;
 DELETE FROM public.dlv_owner_page_unlocks WHERE user_id=auth.uid() AND session_id IS DISTINCT FROM v_sid::text;
 DELETE FROM private.dlv_password_attempts WHERE user_id=auth.uid();
 INSERT INTO public.dlv_security_audit(actor,entity,entity_id,action,changes) VALUES(auth.uid(),'auth.users',auth.uid()::text,'OWNER_PASSWORD_CHANGED',jsonb_build_object('leak_check','hibp_range','other_sessions_revoked',true));
 RETURN jsonb_build_object('success',true,'message','تم تغيير كلمة المرور وإغلاق الجلسات الأخرى');
END $$;
REVOKE ALL ON FUNCTION public.dlv_owner_change_login_password(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_owner_change_login_password(text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.dlv_create_account(p_email text, p_password text, p_name text, p_code text, p_job text, p_branch_id integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid:=gen_random_uuid(); em text:=lower(trim(p_email)); n record;
begin
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS DISTINCT FROM 'admin' OR NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Owner verification required' USING ERRCODE='42501'; END IF;
 IF NOT public.dlv_can_access_branch(p_branch_id) THEN RAISE EXCEPTION 'Branch unavailable' USING ERRCODE='42501'; END IF;
 IF octet_length(coalesce(p_password,''))>72 THEN RAISE EXCEPTION 'Password exceeds 72 bytes'; END IF;

 if auth.uid() is null or public.dlv_role() is distinct from 'admin' then raise exception 'للمالك فقط'; end if;
 if not exists(select 1 from public.dlv_branches where id=p_branch_id and active) then raise exception 'الفرع غير موجود أو غير مفعل'; end if;
 select * into n from public.dlv_job_info(p_job);
 if n.new_role is null or n.new_wf is null then raise exception 'الوظيفة غير صالحة'; end if;
 if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'إيميل غير صالح'; end if;
 if length(coalesce(p_password,''))<12 or p_password !~ '[A-Z]' or p_password !~ '[a-z]' or p_password !~ '[0-9]' or p_password !~ '[^A-Za-z0-9]' then
   raise exception 'كلمة السر يجب أن تكون 12 حرفًا على الأقل وتحتوي على حرف كبير وصغير ورقم ورمز';
 end if;
 if coalesce(trim(p_name),'')='' or length(trim(p_name))>120 or coalesce(trim(p_code),'')='' or length(trim(p_code))>40 then raise exception 'الاسم والكود مطلوبين وبحد أقصى 120 و40 حرفًا'; end if;
 if exists(select 1 from auth.users where lower(email)=em) then raise exception 'الإيميل مسجل بالفعل'; end if;
 if exists(select 1 from public.dlv_profiles where employee_code=trim(p_code)) then raise exception 'كود الموظف مستخدم بالفعل'; end if;
 insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
 values('00000000-0000-0000-0000-000000000000',v_id,'authenticated','authenticated',em,private.dlv_checked_password_hash(p_password),now(),'{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now(),'','','','');
 insert into auth.identities(id,user_id,identity_data,provider,provider_id,last_sign_in_at,created_at,updated_at)
 values(gen_random_uuid(),v_id,jsonb_build_object('sub',v_id::text,'email',em,'email_verified',true),'email',v_id::text,now(),now(),now());
 insert into public.dlv_profiles(user_id,employee_code,full_name,branch_id,allowed_branch_ids,role,job_title,workflow_role)
 values(v_id,trim(p_code),trim(p_name),p_branch_id,array[p_branch_id],n.new_role,n.new_title,n.new_wf);
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.dlv_set_pilot_password(p_user uuid, p_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin

 IF NOT public.dlv_session_valid() OR public.dlv_role() IS DISTINCT FROM 'admin' OR NOT public.dlv_owner_page_check()
 THEN RAISE EXCEPTION 'Owner verification required' USING ERRCODE='42501'; END IF;
 IF p_user IS NULL OR p_user=auth.uid() OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=p_user AND p.role<>'admin' AND p.workflow_role<>'admin')
 THEN RAISE EXCEPTION 'Employee account required' USING ERRCODE='42501'; END IF;
 IF octet_length(coalesce(p_password,''))>72 THEN RAISE EXCEPTION 'Password exceeds 72 bytes'; END IF;

  if public.dlv_role() is distinct from 'admin' then
    raise exception 'للمدير العام فقط';
  end if;

  if p_user is null or p_user = auth.uid() then
    raise exception 'لا يمكن تغيير كلمة مرور حسابك من هذه الوظيفة';
  end if;

  if length(coalesce(p_password, '')) < 12
     or p_password !~ '[A-Z]'
     or p_password !~ '[a-z]'
     or p_password !~ '[0-9]'
     or p_password !~ '[^A-Za-z0-9]' then
    raise exception 'كلمة المرور يجب أن تكون 12 حرفًا على الأقل وتحتوي على حرف كبير وصغير ورقم ورمز';
  end if;

  if not exists (
    select 1 from public.dlv_profiles where user_id = p_user
  ) then
    raise exception 'الحساب غير موجود';
  end if;

  update auth.users
  set encrypted_password = private.dlv_checked_password_hash(p_password),
      updated_at = now()
  where id = p_user;

  DELETE FROM auth.refresh_tokens WHERE user_id=p_user::text;
  DELETE FROM auth.sessions WHERE user_id=p_user;
  DELETE FROM public.dlv_owner_page_unlocks WHERE user_id=p_user;
  INSERT INTO public.dlv_security_audit(actor,entity,entity_id,action,changes)
  VALUES(auth.uid(),'dlv_profiles',p_user::text,'CREDENTIAL_RESET',jsonb_build_object('kind','password','sessions_revoked',true));
end;
$function$
;
