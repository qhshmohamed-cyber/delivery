-- Applied through Supabase migrations: fix_scoped_stage_delay_alerts and reject_missing_effective_role_in_complaints.
-- No customer or employee data is included.
create or replace function public.dlv_followup_pulse(p_branch integer default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_role text:=public.dlv_role(); v_result jsonb;
begin
 if auth.uid() is null or v_role is null or v_role not in ('admin','manager','supervisor','callcenter_followup','complaints_officer') then raise exception 'غير مصرح'; end if;
 if p_branch is not null and not public.dlv_can_access_branch(p_branch) then raise exception 'فرع غير مصرح'; end if;
 with scoped as (
 select o.*,coalesce(s.kitchen_minutes,25) kitchen_limit,coalesce(s.dispatch_minutes,20) dispatch_limit,coalesce(s.delivery_minutes,60) delivery_limit
 from public.dlv_orders o left join public.dlv_branch_sla s on s.branch_id=o.branch_id
 where (o.status in ('new','received','out') or o.order_date=(now() at time zone 'Africa/Cairo')::date)
 and (p_branch is null or o.branch_id=p_branch) and public.dlv_can_access_branch(o.branch_id)
 ), timed as (
 select *,case when status='out' then coalesce(out_at,received_at,created_at)
 when status='received' or workflow_stage='driver_assigned' then coalesce(received_at,pilot_assigned_at,supervisor_received_at,kitchen_ready_at,created_at)
 when workflow_stage in ('kitchen_ready','supervisor_received') then coalesce(kitchen_ready_at,supervisor_received_at,created_at)
 else coalesce(kitchen_received_at,created_at) end stage_started_at,
 case when status='out' then delivery_limit when status='received' or workflow_stage in ('driver_assigned','kitchen_ready','supervisor_received') then dispatch_limit else kitchen_limit end limit_minutes,
 case when status='out' then 'تأخير التوصيل' when status='received' or workflow_stage='driver_assigned' then 'تأخير خروج الطيار' when workflow_stage in ('kitchen_ready','supervisor_received') then 'تأخير إسناد الطيار' else 'تأخير المطبخ' end reason
 from scoped where status in ('new','received','out')
 ), alerts as (
 select *,greatest(0,floor(extract(epoch from (now()-stage_started_at))/60))::integer elapsed_minutes
 from timed where now()-stage_started_at>make_interval(mins=>limit_minutes)
 )
 select jsonb_build_object(
 'active',(select count(*) from timed),
 'delivered',(select count(*) from scoped where status='delivered'),
 'delayed',(select count(*) from alerts),
 'alerts',coalesce((select jsonb_agg(to_jsonb(x)) from
 (select id,branch_id,order_no,status,reason,stage_started_at,elapsed_minutes,limit_minutes
 from alerts order by elapsed_minutes-limit_minutes desc,id desc limit 50) x),'[]'::jsonb))
 into v_result;
 return v_result;
end $$;
revoke all on function public.dlv_followup_pulse(integer) from public,anon;
grant execute on function public.dlv_followup_pulse(integer) to authenticated;
CREATE OR REPLACE FUNCTION public.dlv_complaint_followup(p_incident bigint, p_action text, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.dlv_incidents; v_role text:=public.dlv_role();
begin
 if auth.uid() is null or v_role is null or v_role not in ('admin','manager','complaints_officer') then raise exception 'غير مصرح'; end if;
 if length(trim(coalesce(p_action,''))) not between 3 and 1500 or p_status not in ('open','in_progress','resolved') then raise exception 'بيانات المتابعة غير صحيحة'; end if;
 select * into v from public.dlv_incidents where id=p_incident and category='customer_complaint' for update;
 if not found or (v_role<>'admin' and not public.dlv_can_access_branch(v.branch_id)) then raise exception 'الشكوى غير متاحة'; end if;
 insert into public.dlv_complaint_actions(incident_id,actor,action_text,status_after) values(p_incident,auth.uid(),trim(p_action),p_status);
 update public.dlv_incidents set followup_action=trim(p_action),followup_by=auth.uid(),followup_at=now(),status=p_status,updated_at=now(),resolved_at=case when p_status='resolved' then now() else null end where id=p_incident;
 insert into public.dlv_security_audit(actor,branch_id,entity,entity_id,action,changes) values(auth.uid(),v.branch_id,'dlv_incidents',p_incident::text,'FOLLOWUP',jsonb_build_object('status',p_status,'action_logged',true));
 return jsonb_build_object('success',true);
end $function$;
CREATE OR REPLACE FUNCTION public.dlv_complaint_inbox(p_branch integer DEFAULT NULL::integer)
 RETURNS TABLE(id bigint, branch_id integer, order_no text, customer_phone text, title text, details text, priority text, status text, created_at timestamp with time zone, updated_at timestamp with time zone, followup_action text, followup_at timestamp with time zone, followup_employee text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_role text:=public.dlv_role();
begin
 if auth.uid() is null or v_role is null or v_role not in ('admin','manager','complaints_officer') then raise exception 'غير مصرح'; end if;
 if p_branch is not null and v_role<>'admin' and not public.dlv_can_access_branch(p_branch) then raise exception 'فرع غير مصرح'; end if;
 return query
 select i.id,i.branch_id,o.order_no,o.phone,i.title,i.details,i.priority,i.status,i.created_at,i.updated_at,i.followup_action,i.followup_at,p.full_name
 from public.dlv_incidents i left join public.dlv_orders o on o.id=i.order_id
 left join public.dlv_profiles p on p.user_id=i.followup_by
 where i.category='customer_complaint'
 and (p_branch is null or i.branch_id=p_branch)
 and (v_role='admin' or public.dlv_can_access_branch(i.branch_id))
 order by i.created_at desc limit 300;
end $function$;
CREATE OR REPLACE FUNCTION public.dlv_followup_archive(p_kind text, p_day date DEFAULT NULL::date, p_branch integer DEFAULT NULL::integer, p_query text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_role text:=public.dlv_role(); v_items jsonb; v_day date:=coalesce(p_day,(now() at time zone 'Africa/Cairo')::date);v_q text:=left(trim(coalesce(p_query,'')),60);
begin
 if auth.uid() is null or v_role is null or v_role not in ('admin','manager','supervisor','callcenter_followup','complaints_officer') then raise exception 'غير مصرح';end if;
 if p_kind not in ('cancelled','problems') then raise exception 'نوع غير صحيح';end if;
 if p_branch is not null and not public.dlv_can_access_branch(p_branch) then raise exception 'فرع غير مصرح';end if;
 if p_kind='cancelled' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from
  (select o.id,o.branch_id,o.order_no,o.order_date,o.customer_name,o.phone,o.status,o.failed_reason,o.created_at
   from public.dlv_orders o where o.status='cancelled' and o.order_date=v_day
   and (p_branch is null or o.branch_id=p_branch) and public.dlv_can_access_branch(o.branch_id)
   and (v_q='' or o.order_no ilike '%'||v_q||'%' or o.phone ilike '%'||v_q||'%')
   order by o.created_at desc limit 500) x;
 else
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from
  (select 'incident'::text item_type,i.id,i.branch_id,coalesce(o.order_no,'—') order_no,
    i.created_at,i.title,i.details,i.status,i.followup_action,p.full_name followup_employee
   from public.dlv_incidents i left join public.dlv_orders o on o.id=i.order_id
   left join public.dlv_profiles p on p.user_id=i.followup_by
   where (i.created_at at time zone 'Africa/Cairo')::date=v_day
   and (p_branch is null or i.branch_id=p_branch) and public.dlv_can_access_branch(i.branch_id)
   and (v_q='' or coalesce(o.order_no,'') ilike '%'||v_q||'%' or i.title ilike '%'||v_q||'%')
   union all
   select 'failed_order'::text,o.id,o.branch_id,o.order_no,o.created_at,
   'تعذر التوصيل'::text,coalesce(o.failed_reason,''),o.status,null::text,null::text
   from public.dlv_orders o where o.status='failed' and o.order_date=v_day
   and (p_branch is null or o.branch_id=p_branch) and public.dlv_can_access_branch(o.branch_id)
   and (v_q='' or o.order_no ilike '%'||v_q||'%')
   order by created_at desc limit 500) x;
 end if;
 return jsonb_build_object('kind',p_kind,'day',v_day,'count',jsonb_array_length(v_items),'items',v_items);
end $function$
;