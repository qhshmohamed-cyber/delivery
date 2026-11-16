CREATE OR REPLACE FUNCTION public.dlv_track(p_code text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
 o public.dlv_orders;
 p public.dlv_profiles;
 l public.dlv_locations;
 v_code text := upper(trim(coalesce(p_code,'')));
 v_headers jsonb;
 v_ip inet;
 v_client_key text;
 v_count integer;
begin
 if v_code !~ '^[A-HJ-NP-Z2-9]{8}$' then return json_build_object('found',false); end if;
 begin
  v_headers := coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
  v_ip := nullif(split_part(coalesce(v_headers->>'x-forwarded-for',v_headers->>'x-real-ip',''),',',1),'')::inet;
 exception when others then v_ip := null; end;
 v_client_key := private.dlv_public_request_key('track');
 insert into private.dlv_public_rating_rate_limits(client_key,window_started_at,request_count)
 values(v_client_key,now(),1)
 on conflict(client_key) do update set
 request_count=case when private.dlv_public_rating_rate_limits.window_started_at < now()-interval '1 minute' then 1 else private.dlv_public_rating_rate_limits.request_count+1 end,
 window_started_at=case when private.dlv_public_rating_rate_limits.window_started_at < now()-interval '1 minute' then now() else private.dlv_public_rating_rate_limits.window_started_at end
 returning request_count into v_count;
 if (v_ip is null and v_count>600) or (v_ip is not null and v_count>60) then return json_build_object('found',false,'limited',true); end if;
 select * into o from public.dlv_orders where track_code=v_code;
 if not found OR o.created_at<now()-interval '72 hours' then return json_build_object('found',false); end if;
 if not exists(select 1 from public.dlv_branches b join public.dlv_companies c on c.id=b.company_id where b.id=o.branch_id and b.active and c.active and c.onboarding_status='active') then return json_build_object('found',false); end if;
 if o.status in ('delivered','failed','cancelled') and coalesce(o.delivered_at,o.created_at)<now()-interval '6 hours' then return json_build_object('found',false,'expired',true); end if;
 if o.driver_id is not null then
  select * into p from public.dlv_profiles where user_id=o.driver_id and active=true and role='driver' and workflow_role='driver';
  if o.status='out' and p.user_id is not null then select * into l from public.dlv_locations where driver_id=o.driver_id and branch_id=o.branch_id and updated_at>clock_timestamp()-interval '1 minute' and coalesce(recorded_at,updated_at)>clock_timestamp()-interval '1 minute' and coalesce(recorded_at,updated_at)<=clock_timestamp()+interval '5 seconds' and accuracy between 0 and 150; end if;
 end if;
 return json_build_object('found',true,'order_no',o.order_no,'status',o.status,'stage',o.workflow_stage,
 'out_at',o.out_at,'delivered_at',o.delivered_at,'pilot_name',split_part(btrim(p.full_name),' ',1), 'pilot_reassigned',(select count(*)>1 from public.dlv_workflow_events e where e.order_id=o.id and e.assigned_pilot is not null),
 'pilot_phone',case when o.driver_id is not null and p.user_id=o.driver_id and p.active=true and o.status not in ('failed','cancelled') then nullif(btrim(p.phone),'') else null end,
 'lat',case when o.status='out' then l.lat end,'lng',case when o.status='out' then l.lng end,
 'loc_at',case when o.status='out' then coalesce(l.recorded_at,l.updated_at) end,'accuracy',case when o.status='out' then l.accuracy end,'server_at',clock_timestamp(),
 'brand',(select json_build_object('name',coalesce(nullif(cb.brand_name,'') ,c.name),'logo_url',cb.logo_url,'brand_color',cb.brand_color,'gold_color',cb.gold_color) from public.dlv_branches b join public.dlv_companies c on c.id=b.company_id left join public.dlv_company_branding cb on cb.company_id=c.id where b.id=o.branch_id),'rated',exists(select 1 from public.dlv_customer_ratings where order_id=o.id));
end $function$

