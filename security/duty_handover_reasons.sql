create table if not exists private.dlv_driver_duty(
 user_id uuid primary key references auth.users(id),state text not null check(state in ('available','delivering','break','off_shift')),updated_at timestamptz not null default now()
);
alter table private.dlv_driver_duty enable row level security;
revoke all on private.dlv_driver_duty from public,anon,authenticated;
create table if not exists private.dlv_shift_handovers(
 id uuid primary key default gen_random_uuid(),branch_id integer not null references public.dlv_branches(id),workflow_role text not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),note text not null default '',snapshot jsonb not null,
 accepted_by uuid references auth.users(id),accepted_at timestamptz,check(length(note)<=500)
);
alter table private.dlv_shift_handovers enable row level security;
revoke all on private.dlv_shift_handovers from public,anon,authenticated;
create index if not exists dlv_shift_handovers_branch_role_time on private.dlv_shift_handovers(branch_id,workflow_role,created_at desc);
alter table private.dlv_stage_followups add column if not exists reason_code text check(reason_code in ('kitchen_load','waiting_driver','traffic','customer_unreachable','address_issue','other','unknown'));
create or replace function public.dlv_my_driver_duty() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb;n integer;d private.dlv_driver_duty;
begin
 if auth.uid() is null or public.dlv_role() is distinct from 'driver' then raise exception 'غير مصرح';end if;
 select count(*) into n from public.dlv_orders where driver_id=auth.uid() and status in ('new','received','out') and public.dlv_can_access_branch(branch_id);
 select * into d from private.dlv_driver_duty where user_id=auth.uid();
 return jsonb_build_object('declared_state',coalesce(d.state,'off_shift'),'state',case when n>0 then 'delivering' when d.updated_at<now()-interval '12 hours' then 'off_shift' else coalesce(d.state,'off_shift') end,'active_orders',n,'updated_at',d.updated_at);
end $$;
create or replace function public.dlv_set_my_driver_duty(p_state text) returns jsonb language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if auth.uid() is null or public.dlv_role() is distinct from 'driver' then raise exception 'غير مصرح';end if;
 if p_state is null or p_state not in ('available','delivering','break','off_shift') then raise exception 'حالة غير صحيحة';end if;
 select count(*) into n from public.dlv_orders where driver_id=auth.uid() and status in ('new','received','out');
 if n>0 and p_state in ('available','break','off_shift') then raise exception 'عندك طلبات جارية؛ أكملها أو اطلب من المشرف معالجتها قبل تغيير الحالة';end if;
 if n=0 and p_state='delivering' then raise exception 'لا توجد طلبات جارية';end if;
 insert into private.dlv_driver_duty(user_id,state,updated_at) values(auth.uid(),p_state,now()) on conflict(user_id) do update set state=excluded.state,updated_at=excluded.updated_at;
 return public.dlv_my_driver_duty();
end $$;
create or replace function public.dlv_create_shift_handover(p_branch integer,p_note text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare r text:=public.dlv_role();j jsonb;i uuid;
begin
 if auth.uid() is null or coalesce(r,'') not in ('admin','manager','supervisor','kitchen','callcenter_followup') or not public.dlv_can_access_branch(p_branch) then raise exception 'غير مصرح';end if;
 if length(coalesce(p_note,''))>500 then raise exception 'الملاحظة بحد أقصى 500 حرف';end if;
 select jsonb_build_object('active_count',count(*),'orders',coalesce(jsonb_agg(jsonb_build_object('order_no',order_no,'stage',workflow_stage,'status',status) order by created_at),'[]'),'captured_at',now()) into j from public.dlv_orders where branch_id=p_branch and status in ('new','received','out') and (r not in ('kitchen','supervisor') or (r='kitchen' and workflow_stage in ('new','kitchen_ready')) or (r='supervisor' and workflow_stage in ('kitchen_ready','supervisor_received','driver_assigned')));
 if r in ('admin','manager','callcenter_followup') then j:=j||jsonb_build_object('open_complaints',(select count(*) from public.dlv_incidents where branch_id=p_branch and category='customer_complaint' and status<>'resolved' and (r in ('admin','manager') or created_by=auth.uid())));end if;
 if exists(select 1 from private.dlv_shift_handovers where branch_id=p_branch and created_by=auth.uid() and accepted_at is null) then raise exception 'يوجد تسليم سابق بانتظار الاستلام';end if;
 insert into private.dlv_shift_handovers(branch_id,workflow_role,created_by,note,snapshot) values(p_branch,r,auth.uid(),trim(coalesce(p_note,'')),j) returning id into i;
 insert into public.dlv_security_audit(actor,branch_id,entity,entity_id,action,changes) values(auth.uid(),p_branch,'shift_handover',i::text,'CREATE',jsonb_build_object('role',r));return i;
end $$;
create or replace function public.dlv_list_shift_handovers(p_branch integer) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text:=public.dlv_role();j jsonb;
begin
 if auth.uid() is null or coalesce(r,'') not in ('admin','manager','supervisor','kitchen','callcenter_followup') or not public.dlv_can_access_branch(p_branch) then raise exception 'غير مصرح';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into j from(select h.id,h.branch_id,h.workflow_role,h.created_at,h.note,h.snapshot,h.accepted_at,h.created_by=auth.uid() is_mine,p.full_name created_by_name,q.full_name accepted_by_name
 from private.dlv_shift_handovers h join public.dlv_profiles p on p.user_id=h.created_by left join public.dlv_profiles q on q.user_id=h.accepted_by where h.branch_id=p_branch and (r in ('admin','manager') or h.workflow_role=r) order by h.created_at desc limit 30)x;return j;
end $$;
create or replace function public.dlv_accept_shift_handover(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare h private.dlv_shift_handovers;r text:=public.dlv_role();
begin
 if auth.uid() is null or coalesce(r,'') not in ('admin','manager','supervisor','kitchen','callcenter_followup') then raise exception 'غير مصرح';end if;
 select * into h from private.dlv_shift_handovers where id=p_id for update;
 if not found or not public.dlv_can_access_branch(h.branch_id) or (r not in ('admin','manager') and r<>h.workflow_role) then raise exception 'التسليم غير متاح';end if;
 if h.created_by=auth.uid() then raise exception 'لا يمكنك استلام تسليم أنشأته بنفسك';end if;
 if h.accepted_at is not null then raise exception 'تم استلام هذا التسليم بالفعل';end if;
 update private.dlv_shift_handovers set accepted_by=auth.uid(),accepted_at=now() where id=p_id;
 insert into public.dlv_security_audit(actor,branch_id,entity,entity_id,action,changes) values(auth.uid(),h.branch_id,'shift_handover',p_id::text,'ACCEPT',jsonb_build_object('role',r));
end $$;
create or replace function public.dlv_record_delay_reason(p_order bigint,p_reason text,p_note text) returns void language plpgsql security definer set search_path='' as $$
declare st text;
begin
 if p_reason is null or p_reason not in ('kitchen_load','waiting_driver','traffic','customer_unreachable','address_issue','other','unknown') then raise exception 'سبب غير صحيح';end if;
 perform public.dlv_record_delay_action(p_order,p_note);
 select stage into st from private.dlv_active_stage_delays where order_id=p_order;
 update private.dlv_stage_followups set reason_code=p_reason where order_id=p_order and stage=st and action_by=auth.uid();
end $$;
create or replace function public.dlv_delay_reason_summary(p_day date,p_branch integer default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text:=public.dlv_role();j jsonb;
begin
 if auth.uid() is null or coalesce(r,'') not in ('admin','manager') or p_day is null then raise exception 'غير مصرح';end if;
 if p_branch is not null and not public.dlv_can_access_branch(p_branch) then raise exception 'فرع غير مصرح';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into j from(select coalesce(f.reason_code,'unknown') reason,count(*) count from private.dlv_stage_followups f join public.dlv_orders o on o.id=f.order_id where (f.first_detected_at at time zone 'Africa/Cairo')::date=p_day and (p_branch is null or o.branch_id=p_branch) and public.dlv_can_access_branch(o.branch_id) group by coalesce(f.reason_code,'unknown') order by count(*) desc)x;return j;
end $$;
revoke all on function public.dlv_my_driver_duty(),public.dlv_set_my_driver_duty(text),public.dlv_create_shift_handover(integer,text),public.dlv_list_shift_handovers(integer),public.dlv_accept_shift_handover(uuid),public.dlv_record_delay_reason(bigint,text,text),public.dlv_delay_reason_summary(date,integer) from public,anon;
grant execute on function public.dlv_my_driver_duty(),public.dlv_set_my_driver_duty(text),public.dlv_create_shift_handover(integer,text),public.dlv_list_shift_handovers(integer),public.dlv_accept_shift_handover(uuid),public.dlv_record_delay_reason(bigint,text,text),public.dlv_delay_reason_summary(date,integer) to authenticated;

CREATE OR REPLACE FUNCTION public.dlv_suggest_drivers(p_order bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.dlv_orders;j jsonb;
begin
 if auth.uid() is null or coalesce(public.dlv_role(),'') not in ('admin','manager','supervisor') then raise exception 'غير مصرح';end if;
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
create unique index if not exists dlv_one_pending_handover on private.dlv_shift_handovers(branch_id,created_by) where accepted_at is null;