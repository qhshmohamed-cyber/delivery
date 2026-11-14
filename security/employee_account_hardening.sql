-- Employee account security: preserve accounts and operational data.
-- Apply atomically; customer tracking remains intentionally public.
SET lock_timeout = '5s';
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.dlv_session_valid()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT EXISTS (
  SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
  JOIN public.dlv_profiles p ON p.user_id=u.id AND p.active
  WHERE s.id::text=auth.jwt()->>'session_id' AND s.user_id=(SELECT auth.uid())
  AND (s.not_after IS NULL OR s.not_after>now()) AND u.deleted_at IS NULL
  AND (u.banned_until IS NULL OR u.banned_until<=now())
  AND coalesce((auth.jwt()->>'exp')::bigint,0)>extract(epoch from now())
 );
$$;
REVOKE ALL ON FUNCTION public.dlv_session_valid() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_session_valid() TO authenticated,service_role;

;
CREATE OR REPLACE FUNCTION public.dlv_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
select case when p.role='admin' and p.workflow_role='admin' then 'admin'
when p.workflow_role='custom_unassigned' then 'custom_unassigned'
when p.workflow_role in ('driver','callcenter_followup','kitchen','manager','supervisor','complaints_officer') then p.workflow_role
else p.role end
from public.dlv_profiles p where p.user_id=(select auth.uid()) and p.active=true and public.dlv_session_valid()
and ((p.role='admin' and p.workflow_role='admin') or exists(
select 1 from public.dlv_branches b join public.dlv_companies c on c.id=b.company_id
where b.id=p.branch_id and b.active=true and c.active=true and c.onboarding_status='active'));
$function$

;
CREATE OR REPLACE FUNCTION public.dlv_wf()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT public.dlv_role();
$$;
CREATE OR REPLACE FUNCTION public.dlv_branch()
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT p.branch_id FROM public.dlv_profiles p WHERE p.user_id=(SELECT auth.uid())
 AND p.active AND public.dlv_role() IS NOT NULL;
$$;
CREATE OR REPLACE FUNCTION public.dlv_owner_page_check()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT public.dlv_session_valid()
 AND EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=(SELECT auth.uid()) AND p.active AND p.role='admin' AND p.workflow_role='admin')
 AND (EXISTS(SELECT 1 FROM public.dlv_owner_page_unlocks u WHERE u.user_id=(SELECT auth.uid()) AND u.session_id=auth.jwt()->>'session_id' AND u.expires_at>now())
 OR NOT EXISTS(SELECT 1 FROM public.dlv_owner_page_security p WHERE p.user_id=(SELECT auth.uid())));
$$;

;
CREATE OR REPLACE FUNCTION public.dlv_can_access_branch(p_branch integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT EXISTS(
 SELECT 1 FROM public.dlv_profiles p
 JOIN public.dlv_branches target ON target.id=p_branch AND target.active=true
 JOIN public.dlv_companies company ON company.id=target.company_id AND company.active=true AND company.onboarding_status='active'
 LEFT JOIN public.dlv_branches home ON home.id=p.branch_id
 WHERE p.user_id=(SELECT auth.uid()) AND p.active=true AND public.dlv_role() IS NOT NULL
 AND ((p.role='admin' AND p.workflow_role='admin' AND public.dlv_owner_page_check())
 OR (home.company_id=target.company_id AND (p.branch_id=p_branch OR p_branch=ANY(coalesce(p.allowed_branch_ids,'{}'::integer[])))))
 ) $function$

;
CREATE OR REPLACE FUNCTION public.dlv_my_branches()
 RETURNS TABLE(id integer, name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT DISTINCT b.id,b.name FROM public.dlv_profiles p
 JOIN public.dlv_branches home ON home.id=p.branch_id
 JOIN public.dlv_branches b ON b.company_id=home.company_id
 JOIN public.dlv_companies c ON c.id=b.company_id
 WHERE p.user_id=(SELECT auth.uid()) AND p.active=true AND public.dlv_role() IS NOT NULL
 AND b.active=true AND c.active=true AND c.onboarding_status='active'
 AND ((p.role='admin' AND p.workflow_role='admin' AND public.dlv_owner_page_check())
 OR b.id=p.branch_id OR b.id=ANY(coalesce(p.allowed_branch_ids,'{}'::integer[])))
 ORDER BY b.id $function$

;
DO $patch$
DECLARE f record; definition text; guard text;
BEGIN
 FOR f IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 JOIN pg_language l ON l.oid=p.prolang
 WHERE n.nspname='public' AND p.proname LIKE 'dlv_%' AND l.lanname='plpgsql' AND p.prosecdef
 AND has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND p.proname NOT IN ('dlv_customer_track','dlv_track','dlv_submit_customer_rating')
 LOOP
  definition:=pg_get_functiondef(f.oid);
  guard:=E'\n IF NOT public.dlv_session_valid() OR public.dlv_role() IS NULL THEN RAISE EXCEPTION ''Session invalid or account unavailable'' USING ERRCODE=''42501''; END IF;\n';
  IF f.proname NOT IN ('dlv_owner_page_status','dlv_owner_page_unlock','dlv_owner_page_set_password') THEN
   guard:=guard||E' IF public.dlv_role()=''admin'' AND NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION ''Owner verification required'' USING ERRCODE=''42501''; END IF;\n';
  END IF;
  -- First BEGIN is the outer function body, before any caller-driven operation.
  definition:=regexp_replace(definition,'\mBEGIN\M','BEGIN'||guard,'i');
  EXECUTE definition;
 END LOOP;
END $patch$;

-- Realtime and direct table access use the same live-session boundary.
DO $policies$
DECLARE t record; predicate text;
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind='r' AND c.relname LIKE 'dlv_%'
 LOOP
  predicate:='(SELECT public.dlv_session_valid())';
  IF t.relname<>'dlv_profiles' THEN
   predicate:=predicate||' AND ((SELECT public.dlv_role()) IS DISTINCT FROM ''admin'' OR (SELECT public.dlv_owner_page_check()))';
  END IF;
  EXECUTE format('CREATE POLICY dlv_live_session_boundary ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (%s) WITH CHECK (%s)',t.relname,predicate,predicate);
 END LOOP;
END $policies$;
ALTER POLICY p_sel ON public.dlv_profiles USING (
 user_id=(SELECT auth.uid()) OR ((SELECT public.dlv_role())='admin' AND (SELECT public.dlv_owner_page_check()))
 OR ((SELECT public.dlv_role())='manager' AND public.dlv_can_access_branch(branch_id))
);

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
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf',12)),
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
CREATE OR REPLACE FUNCTION public.dlv_set_pilot_email(p_user uuid, p_email text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare em text := lower(trim(p_email));
begin

 IF NOT public.dlv_session_valid() OR public.dlv_role() IS DISTINCT FROM 'admin' OR NOT public.dlv_owner_page_check()
 THEN RAISE EXCEPTION 'Owner verification required' USING ERRCODE='42501'; END IF;
 IF p_user IS NULL OR p_user=auth.uid() OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=p_user AND p.role<>'admin' AND p.workflow_role<>'admin')
 THEN RAISE EXCEPTION 'Employee account required' USING ERRCODE='42501'; END IF;

  if dlv_role() is distinct from 'admin' then raise exception 'للمدير العام فقط'; end if;
  if p_user = auth.uid() then raise exception 'غيّر إيميلك إنت من Supabase مباشرة'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'إيميل غير صالح'; end if;
  if not exists (select 1 from dlv_profiles where user_id = p_user) then raise exception 'الحساب غير موجود'; end if;
  if exists (select 1 from auth.users where lower(email) = em and id <> p_user) then raise exception 'الإيميل مستخدم بحساب تاني'; end if;
  update auth.users set email = em, updated_at = now() where id = p_user;
  update auth.identities set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(em)), updated_at = now()
  where user_id = p_user and provider = 'email';

  DELETE FROM auth.refresh_tokens WHERE user_id=p_user::text;
  DELETE FROM auth.sessions WHERE user_id=p_user;
  DELETE FROM public.dlv_owner_page_unlocks WHERE user_id=p_user;
  INSERT INTO public.dlv_security_audit(actor,entity,entity_id,action,changes)
  VALUES(auth.uid(),'dlv_profiles',p_user::text,'CREDENTIAL_RESET',jsonb_build_object('kind','email','sessions_revoked',true));
end $function$

;
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
 values('00000000-0000-0000-0000-000000000000',v_id,'authenticated','authenticated',em,extensions.crypt(p_password,extensions.gen_salt('bf',12)),now(),'{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now(),'','','','');
 insert into auth.identities(id,user_id,identity_data,provider,provider_id,last_sign_in_at,created_at,updated_at)
 values(gen_random_uuid(),v_id,jsonb_build_object('sub',v_id::text,'email',em,'email_verified',true),'email',v_id::text,now(),now(),now());
 insert into public.dlv_profiles(user_id,employee_code,full_name,branch_id,allowed_branch_ids,role,job_title,workflow_role)
 values(v_id,trim(p_code),trim(p_name),p_branch_id,array[p_branch_id],n.new_role,n.new_title,n.new_wf);
 return v_id;
end $function$

;
CREATE OR REPLACE FUNCTION public.dlv_customer_order_count(p_branch_id integer, p_phone text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_company bigint; v_digits text; v_count bigint;
begin
 IF NOT public.dlv_session_valid() OR coalesce(public.dlv_role(),'') NOT IN ('admin','manager','callcenter_followup','complaints_officer') OR (public.dlv_role()='admin' AND NOT public.dlv_owner_page_check()) THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 if auth.uid() is null or public.dlv_role() is null or not public.dlv_can_access_branch(p_branch_id) then raise exception 'not authorized'; end if;
 select b.company_id into v_company from public.dlv_branches b join public.dlv_companies c on c.id=b.company_id where b.id=p_branch_id and b.active and c.active and c.onboarding_status='active';
 if v_company is null then raise exception 'branch inactive'; end if;
 v_digits:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
 if v_digits='' then return 0; end if;
 if left(v_digits,2)='20' and length(v_digits)=12 then v_digits:='0'||substr(v_digits,3); end if;
 if length(v_digits)<>11 or v_digits !~ '^01[0125][0-9]{8}$' then return 0; end if;
 select count(*) into v_count from public.dlv_orders o join public.dlv_branches b on b.id=o.branch_id
 where b.company_id=v_company and public.dlv_can_access_branch(o.branch_id) and
 (case when regexp_replace(coalesce(o.phone,''),'[^0-9]','','g') ~ '^20[0-9]{10}$'
 then '0'||substr(regexp_replace(o.phone,'[^0-9]','','g'),3)
 else regexp_replace(coalesce(o.phone,''),'[^0-9]','','g') end)=v_digits;
 return v_count;
end $function$

;
CREATE OR REPLACE FUNCTION public.dlv_set_note(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o dlv_orders; r text := dlv_role();
begin
  if NOT public.dlv_session_valid() OR r is distinct from 'driver' then raise exception 'غير مصرح'; end if;
  select * into o from dlv_orders where id = p_id for update;
  if not found or o.driver_id IS DISTINCT FROM auth.uid() OR NOT public.dlv_can_access_branch(o.branch_id) then raise exception 'ده مش طلبك'; end if;
  if o.status not in ('new','received','out') then raise exception 'لا يمكن إضافة ملاحظة بعد إنهاء الطلب'; end if;
  update dlv_orders set driver_note = nullif(trim(p_note),'') where id = p_id;
  insert into dlv_events(order_id, actor, from_status, to_status, note)
  values (p_id, auth.uid(), o.status, o.status, 'ملاحظة الطيار: ' || coalesce(trim(p_note),''));
end $function$

;
CREATE OR REPLACE FUNCTION public.dlv_set_status(p_id bigint, p_to text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o public.dlv_orders;
  r text := public.dlv_role();
  v_wf text := public.dlv_wf();
  v_stage text;
BEGIN
 IF NOT public.dlv_session_valid() OR r IS NULL OR (r='admin' AND NOT public.dlv_owner_page_check()) THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 IF p_to='cancelled' AND NOT EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=auth.uid() AND p.active AND ((p.role='admin' AND p.workflow_role='admin') OR p.can_cancel_orders)) THEN RAISE EXCEPTION 'Cancellation permission required' USING ERRCODE='42501'; END IF;

  IF auth.uid() IS NULL OR r IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;

  SELECT * INTO o FROM public.dlv_orders WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطلب غير موجود'; END IF;
  IF NOT public.dlv_can_access_branch(o.branch_id) THEN
    RAISE EXCEPTION 'طلب من فرع آخر';
  END IF;

  IF r = 'driver' THEN
    IF v_wf <> 'driver' OR o.driver_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'ده مش طلبك';
    END IF;
    IF p_to NOT IN ('received','out','delivered','failed') THEN
      RAISE EXCEPTION 'الطيار لا يملك صلاحية هذا الإجراء';
    END IF;
  ELSIF r = 'admin' AND v_wf = 'admin' THEN
    NULL;
  ELSIF r = 'manager' AND v_wf = 'manager' THEN
    IF p_to <> 'cancelled' THEN
      RAISE EXCEPTION 'المدير يمكنه إلغاء الطلب فقط؛ انتقالات التشغيل من أصحاب المراحل';
    END IF;
  ELSE
    RAISE EXCEPTION 'هذا الدور لا يملك صلاحية تغيير حالة التوصيل';
  END IF;

  IF p_to = 'cancelled' AND r = 'driver' THEN
    RAISE EXCEPTION 'الإلغاء من الإدارة فقط';
  END IF;

  IF NOT (
    (o.status = 'new' AND p_to IN ('received','cancelled')) OR
    (o.status = 'received' AND p_to IN ('out','cancelled')) OR
    (o.status = 'out' AND p_to IN ('delivered','failed'))
  ) THEN
    RAISE EXCEPTION 'انتقال غير مسموح: % ← %', o.status, p_to;
  END IF;

  IF p_to = 'received' AND o.driver_id IS NULL THEN
    RAISE EXCEPTION 'حوّل الطلب لطيار الأول';
  END IF;
  IF p_to IN ('received','out','delivered','failed') AND r <> 'driver' AND NOT (r='admin' AND v_wf='admin') THEN
    RAISE EXCEPTION 'تحديث حالات التوصيل للطيار المسند إليه الطلب';
  END IF;
  IF p_to = 'failed' AND COALESCE(trim(p_note), '') = '' THEN
    RAISE EXCEPTION 'اكتب سبب التعذر';
  END IF;

  v_stage := CASE p_to
    WHEN 'received' THEN CASE WHEN o.workflow_stage = 'driver_assigned' THEN 'driver_assigned' ELSE 'kitchen_received' END
    WHEN 'out' THEN 'out_for_delivery'
    WHEN 'delivered' THEN 'delivered'
    WHEN 'failed' THEN 'failed'
    WHEN 'cancelled' THEN 'cancelled'
    ELSE o.workflow_stage
  END;

  UPDATE public.dlv_orders
  SET status = p_to,
      workflow_stage = v_stage,
      received_at = CASE WHEN p_to = 'received' THEN now() ELSE received_at END,
      out_at = CASE WHEN p_to = 'out' THEN now() ELSE out_at END,
      delivered_at = CASE WHEN p_to = 'delivered' THEN now() ELSE delivered_at END,
      failed_reason = CASE WHEN p_to = 'failed' THEN p_note ELSE failed_reason END
  WHERE id = p_id;

  INSERT INTO public.dlv_events(order_id, actor, from_status, to_status, note)
  VALUES (p_id, auth.uid(), o.status, p_to, p_note);

  IF v_stage IS DISTINCT FROM o.workflow_stage THEN
    INSERT INTO public.dlv_workflow_events(order_id, actor, from_stage, to_stage, note)
    VALUES (p_id, auth.uid(), o.workflow_stage, v_stage, p_note);
  END IF;
END;
$function$

;
NOTIFY pgrst, 'reload schema';

-- Bound page-password guessing across all sessions of an owner account.
CREATE TABLE private.dlv_owner_unlock_attempts(
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 window_started_at timestamptz NOT NULL DEFAULT now(),
 attempts integer NOT NULL DEFAULT 0
);
ALTER TABLE private.dlv_owner_unlock_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.dlv_owner_unlock_attempts FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.dlv_owner_page_unlock(p_password text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE h text; sid text:=auth.jwt()->>'session_id'; n integer;
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS DISTINCT FROM 'admin'
 OR sid IS NULL THEN RETURN false; END IF;
 IF octet_length(coalesce(p_password,''))>72 THEN RETURN false; END IF;
 INSERT INTO private.dlv_owner_unlock_attempts(user_id,attempts) VALUES(auth.uid(),1)
 ON CONFLICT(user_id) DO UPDATE SET
 attempts=CASE WHEN dlv_owner_unlock_attempts.window_started_at<=now()-interval '15 minutes' THEN 1 ELSE dlv_owner_unlock_attempts.attempts+1 END,
 window_started_at=CASE WHEN dlv_owner_unlock_attempts.window_started_at<=now()-interval '15 minutes' THEN now() ELSE dlv_owner_unlock_attempts.window_started_at END
 RETURNING attempts INTO n;
 IF n>5 THEN RETURN false; END IF;
 SELECT password_hash INTO h FROM public.dlv_owner_page_security WHERE user_id=auth.uid();
 IF h IS NULL OR extensions.crypt(coalesce(p_password,''),h)<>h THEN RETURN false; END IF;
 DELETE FROM private.dlv_owner_unlock_attempts WHERE user_id=auth.uid();
 INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at)
 VALUES(auth.uid(),sid,now()+interval '30 minutes')
 ON CONFLICT(user_id,session_id) DO UPDATE SET expires_at=excluded.expires_at;
 RETURN true;
END $function$;
NOTIFY pgrst, 'reload schema';
