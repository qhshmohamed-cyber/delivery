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
 if em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'إيميل غير صالح'; end if;
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

