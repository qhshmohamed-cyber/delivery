create or replace function public.dlv_my_stage_limits()
returns table(branch_id integer,kitchen_minutes integer,dispatch_minutes integer,delivery_minutes integer)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or public.dlv_role() is null then raise exception 'غير مصرح';end if;
 return query select b.id,coalesce(s.kitchen_minutes,25),coalesce(s.dispatch_minutes,20),coalesce(s.delivery_minutes,60)
 from public.dlv_branches b left join public.dlv_branch_sla s on s.branch_id=b.id
 where public.dlv_can_access_branch(b.id);
end $$;
revoke all on function public.dlv_my_stage_limits() from public,anon;
grant execute on function public.dlv_my_stage_limits() to authenticated;