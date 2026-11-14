create table if not exists private.dlv_stage_followups (
 order_id bigint not null references public.dlv_orders(id) on delete cascade,
 stage text not null check(stage in ('kitchen','dispatch','departure','delivery')),
 first_detected_at timestamptz not null default now(),stage_started_at timestamptz not null,
 action_at timestamptz,action_by uuid references auth.users(id),action_note text,
 escalated_at timestamptz,resolved_at timestamptz,primary key(order_id,stage)
);
alter table private.dlv_stage_followups enable row level security;
revoke all on private.dlv_stage_followups from public,anon,authenticated;
create or replace view private.dlv_active_stage_delays as
select o.id order_id,o.branch_id,o.order_no,o.driver_id,
 case when o.status='out' then 'delivery' when o.status='received' or o.workflow_stage='driver_assigned' then 'departure' when o.workflow_stage in ('kitchen_ready','supervisor_received') then 'dispatch' else 'kitchen' end stage,
 case when o.status='out' then coalesce(o.out_at,o.received_at,o.created_at) when o.status='received' or o.workflow_stage='driver_assigned' then coalesce(o.received_at,o.pilot_assigned_at,o.created_at) when o.workflow_stage in ('kitchen_ready','supervisor_received') then coalesce(o.kitchen_ready_at,o.supervisor_received_at,o.created_at) else coalesce(o.kitchen_received_at,o.created_at) end started_at,
 case when o.status='out' then coalesce(s.delivery_minutes,60) when o.status='received' or o.workflow_stage in ('driver_assigned','kitchen_ready','supervisor_received') then coalesce(s.dispatch_minutes,20) else coalesce(s.kitchen_minutes,25) end limit_minutes
from public.dlv_orders o join public.dlv_branches b on b.id=o.branch_id and b.active
join public.dlv_companies c on c.id=b.company_id and c.active and c.onboarding_status='active'
left join public.dlv_branch_sla s on s.branch_id=o.branch_id where o.status in ('new','received','out');
revoke all on private.dlv_active_stage_delays from public,anon,authenticated;
create or replace function private.dlv_scan_stage_delays(p_branch integer default null)
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtext('dlv_stage_scan'),coalesce(p_branch,0)) then return 0;end if;
 update private.dlv_stage_followups f set resolved_at=now() from public.dlv_orders o where o.id=f.order_id and (p_branch is null or o.branch_id=p_branch) and f.resolved_at is null and not exists(select 1 from private.dlv_active_stage_delays a where a.order_id=f.order_id and a.stage=f.stage);
 insert into private.dlv_stage_followups(order_id,stage,stage_started_at)
 select a.order_id,a.stage,a.started_at from private.dlv_active_stage_delays a where (p_branch is null or a.branch_id=p_branch) and now()>a.started_at+make_interval(mins=>a.limit_minutes)
 on conflict(order_id,stage) do nothing;
 insert into public.dlv_notifications(user_id,order_id,notification_type,title,body)
 select p.user_id,a.order_id,'stage_delay_'||a.stage,'طلب يحتاج إجراء متابعة','الطلب #'||a.order_no||' تجاوز الحد المحدد للمرحلة. سجّل الإجراء في ملف الطلب.'
 from private.dlv_active_stage_delays a join private.dlv_stage_followups f on f.order_id=a.order_id and f.stage=a.stage and f.resolved_at is null
 join public.dlv_branches b on b.id=a.branch_id
 join public.dlv_profiles p on p.active and (p.branch_id=a.branch_id or a.branch_id=any(p.allowed_branch_ids))
 join public.dlv_branches home on home.id=p.branch_id and home.company_id=b.company_id
 where (p_branch is null or a.branch_id=p_branch) and ((a.stage='kitchen' and p.workflow_role in ('kitchen','callcenter_followup')) or (a.stage='dispatch' and p.workflow_role in ('supervisor','callcenter_followup')) or (a.stage in ('departure','delivery') and (p.user_id=a.driver_id or p.workflow_role='callcenter_followup')))
 on conflict(user_id,order_id,notification_type) do nothing;
 insert into public.dlv_notifications(user_id,order_id,notification_type,title,body)
 select p.user_id,a.order_id,'stage_escalated_'||a.stage,'تصعيد للمدير — تأخير بدون إجراء','الطلب #'||a.order_no||' تجاوز حد المرحلة بـ10 دقائق ولم يسجّل المسؤول إجراءً.'
 from private.dlv_active_stage_delays a join private.dlv_stage_followups f on f.order_id=a.order_id and f.stage=a.stage and f.resolved_at is null and f.action_at is null
 join public.dlv_branches b on b.id=a.branch_id join public.dlv_profiles p on p.active
 left join public.dlv_branches home on home.id=p.branch_id
 where (p_branch is null or a.branch_id=p_branch) and now()>a.started_at+make_interval(mins=>a.limit_minutes+10)
 and ((p.role='admin' and p.workflow_role='admin') or (p.workflow_role='manager' and home.company_id=b.company_id and (p.branch_id=a.branch_id or a.branch_id=any(p.allowed_branch_ids))))
 on conflict(user_id,order_id,notification_type) do nothing;
 get diagnostics v_count=row_count;
 update private.dlv_stage_followups f set escalated_at=coalesce(f.escalated_at,now()) from private.dlv_active_stage_delays a where f.order_id=a.order_id and f.stage=a.stage and (p_branch is null or a.branch_id=p_branch) and f.action_at is null and now()>a.started_at+make_interval(mins=>a.limit_minutes+10);
 return v_count;
end $$;
revoke all on function private.dlv_scan_stage_delays(integer) from public,anon,authenticated;
-- Replace the legacy recipient query, which did not scope each recipient to the order's company.
create or replace function public.dlv_check_kitchen_delays() returns integer language plpgsql security definer set search_path='' as $$
declare b record;n integer:=0;
begin
 if auth.uid() is null or coalesce(public.dlv_role(),'') not in ('admin','manager','supervisor','callcenter_followup','kitchen','driver') then raise exception 'غير مصرح';end if;
 for b in select id from public.dlv_branches where public.dlv_can_access_branch(id) loop n:=n+private.dlv_scan_stage_delays(b.id);end loop;return n;
end $$;
revoke all on function public.dlv_check_kitchen_delays() from public,anon;
grant execute on function public.dlv_check_kitchen_delays() to authenticated;
create or replace function public.dlv_record_delay_action(p_order bigint,p_note text) returns void language plpgsql security definer set search_path='' as $$
declare o public.dlv_orders;r text:=public.dlv_role();st text;
begin
 if auth.uid() is null or r is null or r not in ('admin','manager','supervisor','callcenter_followup','kitchen','driver') then raise exception 'غير مصرح';end if;
 select * into o from public.dlv_orders where id=p_order;
 if not found or not public.dlv_can_access_branch(o.branch_id) or (r='driver' and o.driver_id is distinct from auth.uid()) then raise exception 'الطلب غير متاح';end if;
 if length(trim(coalesce(p_note,''))) not between 3 and 500 then raise exception 'اكتب الإجراء من 3 إلى 500 حرف';end if;
 select stage into st from private.dlv_active_stage_delays where order_id=p_order;
 if st is null then raise exception 'الطلب غير جارٍ';end if;
 update private.dlv_stage_followups set action_at=now(),action_by=auth.uid(),action_note=trim(p_note) where order_id=p_order and stage=st and resolved_at is null;
 if not found then raise exception 'لا يوجد تنبيه تأخير لهذه المرحلة';end if;
 insert into public.dlv_workflow_events(order_id,actor,from_stage,to_stage,note) values(p_order,auth.uid(),o.workflow_stage,o.workflow_stage,'إجراء تأخير: '||trim(p_note));
end $$;
create or replace function public.dlv_suggest_drivers(p_order bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.dlv_orders;j jsonb;
begin
 if auth.uid() is null or coalesce(public.dlv_role(),'') not in ('admin','manager','supervisor') then raise exception 'غير مصرح';end if;
 select * into o from public.dlv_orders where id=p_order;
 if not found or not public.dlv_can_access_branch(o.branch_id) then raise exception 'الطلب غير متاح';end if;
 if o.status<>'new' or o.workflow_stage not in ('kitchen_ready','supervisor_received') then raise exception 'الطلب ليس جاهزًا للإسناد';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into j from (
 select p.user_id,p.full_name,count(a.id)::integer active_orders,max(l.updated_at) location_updated_at
 from public.dlv_profiles p join public.dlv_branches h on h.id=p.branch_id join public.dlv_branches b on b.id=o.branch_id and b.company_id=h.company_id
 left join public.dlv_orders a on a.driver_id=p.user_id and a.status in ('new','received','out')
 left join public.dlv_locations l on l.driver_id=p.user_id and l.branch_id=o.branch_id
 where p.active and p.role='driver' and p.workflow_role='driver' and o.branch_id=any(p.allowed_branch_ids)
 group by p.user_id,p.full_name order by count(a.id),max(l.updated_at) desc nulls last,p.user_id limit 5) x;
 return j;
end $$;
create or replace function public.dlv_order_dossier(p_order bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.dlv_orders;r text:=public.dlv_role();j jsonb;
begin
 if auth.uid() is null or coalesce(r,'') not in ('admin','manager','supervisor','callcenter_followup') then raise exception 'غير مصرح';end if;
 select * into o from public.dlv_orders where id=p_order;
 if not found or not public.dlv_can_access_branch(o.branch_id) then raise exception 'الطلب غير متاح';end if;
 select jsonb_build_object('order',jsonb_build_object('id',o.id,'order_no',o.order_no,'branch_id',o.branch_id,'status',o.status,'stage',o.workflow_stage,'created_at',o.created_at,'notes',o.notes,'driver_note',o.driver_note),
 'events',coalesce((select jsonb_agg(to_jsonb(x) order by x.at) from(select e.id,e.created_at at,e.to_stage stage,e.note,p.full_name actor from public.dlv_workflow_events e left join public.dlv_profiles p on p.user_id=e.actor where e.order_id=o.id order by e.created_at,e.id limit 500)x),'[]'),
 'complaints',coalesce((select jsonb_agg(to_jsonb(x)) from(select i.id,i.title,i.status,i.followup_action,p.full_name responsible from public.dlv_incidents i left join public.dlv_profiles p on p.user_id=i.followup_by where i.order_id=o.id and i.category='customer_complaint' and (r in ('admin','manager') or i.created_by=auth.uid()) order by i.created_at limit 50)x),'[]'),
 'delay_actions',coalesce((select jsonb_agg(jsonb_build_object('stage',f.stage,'action',f.action_note,'at',f.action_at,'escalated_at',f.escalated_at,'resolved_at',f.resolved_at,'actor',p.full_name)) from private.dlv_stage_followups f left join public.dlv_profiles p on p.user_id=f.action_by where f.order_id=o.id),'[]')) into j;
 return j;
end $$;
create or replace function public.dlv_shift_summary(p_day date,p_shift text default 'full',p_branch integer default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare start_at timestamptz;end_at timestamptz;j jsonb;r text:=public.dlv_role();
begin
 if auth.uid() is null or coalesce(r,'') not in ('admin','manager') then raise exception 'غير مصرح';end if;
 if p_day is null or p_shift not in ('full','morning','evening') then raise exception 'فترة غير صحيحة';end if;
 if p_branch is not null and not public.dlv_can_access_branch(p_branch) then raise exception 'فرع غير مصرح';end if;
 start_at:=(p_day+case p_shift when 'morning' then time '08:00' when 'evening' then time '18:00' else time '07:00' end) at time zone 'Africa/Cairo';
 end_at:=(case when p_shift='morning' then p_day+time '18:00' else (p_day+1)+time '04:00' end) at time zone 'Africa/Cairo';
 with scoped as(select o.*,coalesce(s.kitchen_minutes,25) kitchen_limit,coalesce(s.dispatch_minutes,20) dispatch_limit,coalesce(s.delivery_minutes,60) delivery_limit from public.dlv_orders o left join public.dlv_branch_sla s on s.branch_id=o.branch_id where o.created_at>=start_at and o.created_at<end_at and (p_branch is null or o.branch_id=p_branch) and public.dlv_can_access_branch(o.branch_id)),
 durations as(select *,extract(epoch from(coalesce(kitchen_ready_at,case when workflow_stage='new' and status='new' then now() end)-coalesce(kitchen_received_at,created_at)))/60 kitchen_duration,extract(epoch from(coalesce(out_at,case when status in ('new','received') and kitchen_ready_at is not null then now() end)-kitchen_ready_at))/60 dispatch_duration,extract(epoch from(coalesce(delivered_at,case when status='out' then now() end)-out_at))/60 delivery_duration from scoped)
 select jsonb_build_object('day',p_day,'shift',p_shift,'start_at',start_at,'end_at',end_at,'total',(select count(*) from scoped),'delivered',(select count(*) from scoped where status='delivered'),'cancelled',(select count(*) from scoped where status='cancelled'),'failed',(select count(*) from scoped where status='failed'),'active',(select count(*) from scoped where status in ('new','received','out')),
 'delays',jsonb_build_object('kitchen',(select count(*) from durations where kitchen_duration>kitchen_limit),'dispatch',(select count(*) from durations where dispatch_duration>dispatch_limit),'delivery',(select count(*) from durations where delivery_duration>delivery_limit)),
 'complaints',(select count(*) from public.dlv_incidents i where i.category='customer_complaint' and i.created_at>=start_at and i.created_at<end_at and (p_branch is null or i.branch_id=p_branch) and public.dlv_can_access_branch(i.branch_id)),
 'drivers',coalesce((select jsonb_agg(to_jsonb(x)) from(select p.full_name,count(*) total,count(*) filter(where o.status='delivered') delivered,count(*) filter(where o.status='failed') failed from scoped o join public.dlv_profiles p on p.user_id=o.driver_id group by p.user_id,p.full_name order by count(*) desc)x),'[]')) into j;
 return j;
end $$;
revoke all on function public.dlv_record_delay_action(bigint,text),public.dlv_suggest_drivers(bigint),public.dlv_order_dossier(bigint),public.dlv_shift_summary(date,text,integer) from public,anon;
grant execute on function public.dlv_record_delay_action(bigint,text),public.dlv_suggest_drivers(bigint),public.dlv_order_dossier(bigint),public.dlv_shift_summary(date,text,integer) to authenticated;

create or replace function public.dlv_list_stage_notifications()
returns table(id bigint,order_id bigint,notification_type text,title text,body text,created_at timestamptz,read_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare r text:=public.dlv_role();
begin
 if auth.uid() is null or r is null then raise exception 'غير مصرح';end if;
 return query select n.id,n.order_id,n.notification_type,n.title,n.body,n.created_at,n.read_at
 from public.dlv_notifications n join public.dlv_orders o on o.id=n.order_id
 join private.dlv_active_stage_delays a on a.order_id=o.id
 join private.dlv_stage_followups f on f.order_id=o.id and f.stage=a.stage and f.resolved_at is null
 where n.user_id=auth.uid() and public.dlv_can_access_branch(o.branch_id)
 and (r<>'driver' or o.driver_id=auth.uid())
 and n.notification_type in ('stage_delay_'||a.stage,'stage_escalated_'||a.stage)
 order by n.created_at desc limit 100;
end $$;
revoke all on function public.dlv_list_stage_notifications() from public,anon;
grant execute on function public.dlv_list_stage_notifications() to authenticated;
CREATE OR REPLACE FUNCTION public.dlv_list_notifications()
 RETURNS TABLE(id bigint, order_id bigint, title text, body text, created_at timestamp with time zone, read_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or coalesce(public.dlv_role(),'') not in ('admin','callcenter_followup','manager') then
    raise exception 'الصلاحية للمدير ومتابعة الكول سنتر ومالك النظام فقط';
  end if;
  return query
    select n.id,n.order_id,n.title,n.body,n.created_at,n.read_at
    from public.dlv_notifications n
    join public.dlv_orders o on o.id=n.order_id
    where n.user_id=auth.uid() and public.dlv_can_access_branch(o.branch_id)
      and o.status='new'
      and o.workflow_stage='new'
      and coalesce(o.kitchen_received_at,o.created_at)<=now()-interval '25 minutes'
    order by n.created_at desc
    limit 50;
end
$function$
;
CREATE OR REPLACE FUNCTION public.dlv_order_dossier(p_order bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.dlv_orders;r text:=public.dlv_role();j jsonb;
begin
 if auth.uid() is null or coalesce(r,'') not in ('admin','manager','supervisor','callcenter_followup') then raise exception 'غير مصرح';end if;
 select * into o from public.dlv_orders where id=p_order;
 if not found or not public.dlv_can_access_branch(o.branch_id) then raise exception 'الطلب غير متاح';end if;
 select jsonb_build_object('order',jsonb_build_object('id',o.id,'order_no',o.order_no,'branch_id',o.branch_id,'status',o.status,'stage',o.workflow_stage,'created_at',o.created_at,'notes',o.notes,'driver_note',o.driver_note),
 'events',coalesce((select jsonb_agg(to_jsonb(x) order by x.at) from(select e.id,e.created_at at,e.to_stage stage,e.note,p.full_name actor from public.dlv_workflow_events e left join public.dlv_profiles p on p.user_id=e.actor where e.order_id=o.id union all select e.id,e.at,e.to_status,e.note,p.full_name from public.dlv_events e left join public.dlv_profiles p on p.user_id=e.actor where e.order_id=o.id order by at,id limit 500)x),'[]'),
 'complaints',coalesce((select jsonb_agg(to_jsonb(x)) from(select i.id,i.title,i.status,i.followup_action,p.full_name responsible from public.dlv_incidents i left join public.dlv_profiles p on p.user_id=i.followup_by where i.order_id=o.id and i.category='customer_complaint' and (r in ('admin','manager') or i.created_by=auth.uid()) order by i.created_at limit 50)x),'[]'),
 'delay_actions',coalesce((select jsonb_agg(jsonb_build_object('stage',f.stage,'action',f.action_note,'at',f.action_at,'escalated_at',f.escalated_at,'resolved_at',f.resolved_at,'actor',p.full_name)) from private.dlv_stage_followups f left join public.dlv_profiles p on p.user_id=f.action_by where f.order_id=o.id),'[]')) into j;
 return j;
end $function$
;
-- Scheduled on the server every minute using pg_cron.
-- cron.schedule('dlv-stage-delay-monitor','* * * * *','select private.dlv_scan_stage_delays(null);');
