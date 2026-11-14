CREATE OR REPLACE FUNCTION public.dlv_create_order(p_order_no text, p_customer text, p_phone text, p_address text, p_notes text, p_driver uuid DEFAULT NULL::uuid, p_branch_id integer DEFAULT NULL::integer, p_callcenter_staff_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid:=auth.uid(); v_branch integer; v_wf text; v_id bigint;
begin
 if v_user is null or public.dlv_role() is null then raise exception 'يجب تسجيل الدخول'; end if;
 select branch_id,coalesce(workflow_role,role) into v_branch,v_wf from public.dlv_profiles where user_id=v_user and active=true;
 if not found then raise exception 'الحساب غير نشط'; end if;
 if coalesce(v_wf,'') not in ('callcenter_followup','manager','admin') then raise exception 'إنشاء الطلب لمتابعة الكول سنتر والإدارة فقط'; end if;
 if public.dlv_role()='admin' then
  if p_branch_id is null or not exists(select 1 from public.dlv_branches where id=p_branch_id and active) then raise exception 'حدد الفرع'; end if;
  v_branch:=p_branch_id;
 else
  if p_branch_id is not null and not public.dlv_can_access_branch(p_branch_id) then raise exception 'لا يمكنك إنشاء طلب في هذا الفرع'; end if;
  v_branch:=coalesce(p_branch_id,v_branch);
 end if;
 if p_callcenter_staff_id is null or not exists(select 1 from public.dlv_callcenter_staff where id=p_callcenter_staff_id and branch_id=v_branch and active=true) then raise exception 'اختر موظف الكول سنتر صاحب الطلب من نفس الفرع';end if;
 if coalesce(trim(p_order_no),'')='' then raise exception 'رقم الطلب مطلوب'; end if;
 if p_driver is not null then raise exception 'لا يمكن تعيين الطيار عند إنشاء الطلب؛ يجب مرور الطلب بالمطبخ ثم المشرف'; end if;
 insert into public.dlv_orders(branch_id,order_no,customer_name,phone,address,notes,driver_id,status,created_by,source_role,source_user,workflow_stage,pilot_assigned_at,callcenter_staff_id)
 values(v_branch,trim(p_order_no),nullif(trim(p_customer),''),nullif(trim(p_phone),''),nullif(trim(p_address),''),nullif(trim(p_notes),''),null,'new',v_user,v_wf,v_user,'new',null,p_callcenter_staff_id) returning id into v_id;
 insert into public.dlv_events(order_id,actor,from_status,to_status,note) values(v_id,v_user,null,'new','إنشاء الطلب');
 insert into public.dlv_workflow_events(order_id,actor,from_stage,to_stage,note) values(v_id,v_user,null,'new','إنشاء الطلب');
 return v_id;
exception when unique_violation then raise exception 'رقم الطلب مسجل بالفعل اليوم';
end $function$
;