CREATE OR REPLACE FUNCTION public.dlv_assign_driver(p_order_id bigint, p_driver uuid, p_note text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare o public.dlv_orders; v_role text; v_owner boolean; v_changed boolean;
begin
 v_role:=public.dlv_role(); v_owner:=v_role='admin';
 if auth.uid() is null or coalesce(v_role,'') not in ('supervisor','admin') then raise exception 'إسناد الطلب للمشرف فقط، مع صلاحية تدخل مالك النظام'; end if;
 select * into o from public.dlv_orders where id=p_order_id for update;
 if not found then raise exception 'الطلب غير موجود'; end if;
 if not v_owner and not public.dlv_can_access_branch(o.branch_id) then raise exception 'طلب من فرع آخر'; end if;
 if o.status<>'new' then raise exception 'لا يمكن تغيير الطيار بعد بدء التوصيل أو إغلاق الطلب'; end if;
 if o.workflow_stage not in ('supervisor_received','driver_assigned') or o.supervisor_received_at is null then raise exception 'يجب استلام المشرف للطلب أولا'; end if;
 if o.driver_id is not null and not v_owner then raise exception 'تغيير الطيار بعد تعيينه متاح لصاحب النظام فقط'; end if;
 if not exists(select 1 from public.dlv_profiles d where d.user_id=p_driver and d.role='driver' and d.workflow_role='driver' and d.active and o.branch_id=any(d.allowed_branch_ids)) then raise exception 'الطيار غير نشط أو غير مصرح له بالفرع'; end if;
 if not exists(select 1 from private.dlv_driver_duty duty join public.dlv_profiles dp on dp.user_id=duty.user_id join public.dlv_branches home on home.id=dp.branch_id join public.dlv_branches target on target.id=o.branch_id and target.company_id=home.company_id where duty.user_id=p_driver and duty.state in ('available','delivering') and duty.updated_at>now()-interval '12 hours') then raise exception 'يجب أن يبدأ الطيار شفته ويحدد متاح أو في توصيل أولًا';end if;
 if o.driver_id=p_driver then return json_build_object('success',true,'unchanged',true); end if;
 v_changed:=o.driver_id is not null;
 update public.dlv_orders set driver_id=p_driver,workflow_stage='driver_assigned',pilot_assigned_at=now() where id=p_order_id;
 insert into public.dlv_workflow_events(order_id,actor,from_stage,to_stage,assigned_pilot,note)
 values(p_order_id,auth.uid(),o.workflow_stage,'driver_assigned',p_driver,case when v_changed then 'إعادة تعيين الطيار بواسطة المالك' else left(coalesce(p_note,''),300) end);
 return json_build_object('success',true,'reassigned',v_changed,'order_id',p_order_id);
end $function$
;
CREATE OR REPLACE FUNCTION public.dlv_suggest_drivers(p_order bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.dlv_orders;j jsonb;
begin
 if auth.uid() is null or coalesce(public.dlv_role(),'') not in ('admin','supervisor') then raise exception 'غير مصرح';end if;
 select * into o from public.dlv_orders where id=p_order;
 if not found or not public.dlv_can_access_branch(o.branch_id) then raise exception 'الطلب غير متاح';end if;
 if o.status<>'new' or o.workflow_stage not in ('kitchen_ready','supervisor_received') then raise exception 'الطلب ليس جاهزًا للإسناد';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into j from (
 select p.user_id,p.full_name,case when count(a.id)>0 then 'delivering' else duty.state end duty_state,count(a.id)::integer active_orders,max(l.updated_at) location_updated_at
 from public.dlv_profiles p join private.dlv_driver_duty duty on duty.user_id=p.user_id and duty.state in ('available','delivering') and duty.updated_at>now()-interval '12 hours' join public.dlv_branches h on h.id=p.branch_id join public.dlv_branches b on b.id=o.branch_id and b.company_id=h.company_id
 left join public.dlv_orders a on a.driver_id=p.user_id and a.status in ('new','received','out')
 left join public.dlv_locations l on l.driver_id=p.user_id and l.branch_id=o.branch_id
 where p.active and p.role='driver' and p.workflow_role='driver' and o.branch_id=any(p.allowed_branch_ids)
 group by p.user_id,p.full_name,duty.state order by count(a.id),max(l.updated_at) desc nulls last,p.user_id limit 5) x;
 return j;
end $function$
;