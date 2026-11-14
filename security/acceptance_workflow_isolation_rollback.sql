-- Synthetic acceptance test. Ends in ROLLBACK; never COMMIT this script.
-- Sequence counters can advance during rolled-back inserts.
begin;
create temporary table acceptance_results(test text,passed boolean) on commit drop;
do $$
declare b integer; f uuid; k uuid; s uuid; d uuid; staff bigint; oid bigint; c2 bigint; b2 integer; n bigint; old_orders bigint; number text:='QA-'||substr(gen_random_uuid()::text,1,12); j jsonb;
begin
 select branch_id into b from public.dlv_profiles where active and workflow_role='callcenter_followup' limit 1;
 select user_id into f from public.dlv_profiles where active and branch_id=b and workflow_role='callcenter_followup' limit 1;
 select user_id into k from public.dlv_profiles where active and branch_id=b and workflow_role='kitchen' limit 1;
 select user_id into s from public.dlv_profiles where active and branch_id=b and workflow_role='supervisor' limit 1;
 select user_id into d from public.dlv_profiles where active and branch_id=b and workflow_role='driver' and b=any(allowed_branch_ids) limit 1;
 select id into staff from public.dlv_callcenter_staff where active and branch_id=b limit 1;
 if f is null or k is null or s is null or d is null or staff is null then raise exception 'Missing test role';end if;
 select count(*) into old_orders from public.dlv_orders;
 perform set_config('request.jwt.claim.sub',f::text,true);
 oid:=public.dlv_create_order(number,'QA synthetic customer',null,'QA test address','Rollback acceptance test',null,b,staff);
 begin perform public.dlv_create_order(number,'QA synthetic customer',null,null,null,null,b,staff); raise exception 'Duplicate accepted';exception when raise_exception then if sqlerrm<>'رقم الطلب مسجل بالفعل اليوم' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',d::text,true);
 begin perform public.dlv_set_status(oid,'out',null);raise exception 'Illegal transition accepted';exception when raise_exception then if sqlerrm='Illegal transition accepted' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',k::text,true);perform public.dlv_kitchen_forward(oid,null);
 perform set_config('request.jwt.claim.sub',s::text,true);perform public.dlv_supervisor_receive(oid,null);perform public.dlv_assign_driver(oid,d,null);
 perform set_config('request.jwt.claim.sub',d::text,true);perform public.dlv_set_status(oid,'received',null);perform public.dlv_set_status(oid,'out',null);perform public.dlv_set_status(oid,'delivered',null);
 if not exists(select 1 from public.dlv_orders where id=oid and status='delivered' and received_at is not null and out_at is not null and delivered_at is not null) then raise exception 'Workflow failed';end if;
 if (select count(*) from public.dlv_workflow_events where order_id=oid)<6 then raise exception 'Missing workflow history';end if;
 insert into acceptance_results values('workflow_all_roles_and_duplicate_prevention',true);
 insert into public.dlv_companies(name,slug,active,onboarding_status) values('QA isolated company','qa-'||substr(gen_random_uuid()::text,1,12),true,'active') returning id into c2;
 select coalesce(min(id),0)-1 into b2 from public.dlv_branches; insert into public.dlv_branches(id,name,company_id) values(b2,'QA branch '||gen_random_uuid()::text,c2);
 perform set_config('request.jwt.claim.sub',f::text,true);
 if public.dlv_can_access_branch(b2) then raise exception 'Tenant A accessed B';end if;
 update public.dlv_profiles set branch_id=b2,allowed_branch_ids=array[b2] where user_id=f;
 if public.dlv_can_access_branch(b) or not public.dlv_can_access_branch(b2) then raise exception 'Tenant B scope failed';end if;
 execute 'set local role authenticated';
 select count(*) into n from public.dlv_orders where branch_id=b;
 if n<>0 then raise exception 'Tenant B read tenant A orders';end if;
 execute 'reset role';
 insert into acceptance_results values('second_company_bidirectional_isolation',true);
 if (select count(*) from public.dlv_orders)<>old_orders+1 then raise exception 'Unexpected order count';end if;
end $$;
select * from acceptance_results;
rollback;