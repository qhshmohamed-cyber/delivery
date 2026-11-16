-- Record fix time separately from arrival time; retain the legacy Android RPC.
ALTER TABLE public.dlv_locations ADD COLUMN IF NOT EXISTS recorded_at timestamptz;
CREATE FUNCTION private.dlv_write_location(p_lat double precision,p_lng double precision,p_acc real,p_recorded_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=(SELECT auth.uid());bid integer;at_time timestamptz;fix_time timestamptz;old public.dlv_locations;dt double precision;distance_m double precision;
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS DISTINCT FROM 'driver' THEN RAISE EXCEPTION 'Driver session required' USING ERRCODE='42501';END IF;
 IF p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 OR p_acc IS NULL OR p_acc NOT BETWEEN 0 AND 150 THEN RAISE EXCEPTION 'Invalid coordinates or GPS accuracy' USING ERRCODE='22023';END IF;
 bid:=public.dlv_branch();IF bid IS NULL OR NOT public.dlv_can_access_branch(bid) THEN RAISE EXCEPTION 'Branch unavailable' USING ERRCODE='42501';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('gps:'||uid::text,0));
 at_time:=clock_timestamp();fix_time:=coalesce(p_recorded_at,at_time);
 IF fix_time<at_time-interval '20 seconds' OR fix_time>at_time+interval '5 seconds' THEN RETURN jsonb_build_object('accepted',false,'reason','sample_time');END IF;
 SELECT * INTO old FROM public.dlv_locations WHERE driver_id=uid FOR UPDATE;
 IF FOUND AND old.branch_id=bid THEN
  IF fix_time<=coalesce(old.recorded_at,old.updated_at) THEN RETURN jsonb_build_object('accepted',false,'reason','older_sample');END IF;
  IF old.updated_at>at_time-interval '2 seconds' THEN RETURN jsonb_build_object('accepted',false,'reason','throttled');END IF;
  dt:=extract(epoch FROM fix_time-coalesce(old.recorded_at,old.updated_at));
  IF dt>0 AND old.lat BETWEEN -90 AND 90 AND old.lng BETWEEN -180 AND 180 THEN
   distance_m:=12742000*asin(least(1.0,sqrt(power(sin(radians(p_lat-old.lat)/2),2)+cos(radians(old.lat))*cos(radians(p_lat))*power(sin(radians(p_lng-old.lng)/2),2))));
   IF distance_m>65*dt+coalesce(old.accuracy,150)+p_acc+30 THEN RETURN jsonb_build_object('accepted',false,'reason','implausible_jump');END IF;
  END IF;
 END IF;
 INSERT INTO public.dlv_locations(driver_id,branch_id,lat,lng,accuracy,updated_at,recorded_at) VALUES(uid,bid,p_lat,p_lng,p_acc,at_time,fix_time)
 ON CONFLICT(driver_id) DO UPDATE SET branch_id=excluded.branch_id,lat=excluded.lat,lng=excluded.lng,accuracy=excluded.accuracy,updated_at=excluded.updated_at,recorded_at=excluded.recorded_at;
 RETURN jsonb_build_object('accepted',true);
END $$;
REVOKE ALL ON FUNCTION private.dlv_write_location(double precision,double precision,real,timestamptz) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.dlv_update_location(p_lat double precision,p_lng double precision,p_acc real DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN PERFORM private.dlv_write_location(p_lat,p_lng,p_acc,NULL);END $$;
CREATE FUNCTION public.dlv_update_location_v2(p_lat double precision,p_lng double precision,p_acc real,p_recorded_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_recorded_at IS NULL THEN RAISE EXCEPTION 'Fix time required' USING ERRCODE='22023';END IF;
 RETURN private.dlv_write_location(p_lat,p_lng,p_acc,p_recorded_at);
END $$;
CREATE FUNCTION public.dlv_map_locations(p_branch integer)
RETURNS TABLE(driver_id uuid,branch_id integer,lat double precision,lng double precision,accuracy real,updated_at timestamptz,recorded_at timestamptz,server_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS NULL OR public.dlv_role() NOT IN ('admin','manager','supervisor') OR NOT public.dlv_can_access_branch(p_branch)
 OR (public.dlv_role()='admin' AND NOT public.dlv_owner_page_check()) THEN RAISE EXCEPTION 'Map access denied' USING ERRCODE='42501';END IF;
 RETURN QUERY SELECT l.driver_id,l.branch_id,l.lat,l.lng,l.accuracy,l.updated_at,coalesce(l.recorded_at,l.updated_at),clock_timestamp()
 FROM public.dlv_locations l JOIN public.dlv_profiles p ON p.user_id=l.driver_id AND p.branch_id=l.branch_id
 WHERE l.branch_id=p_branch AND p.active AND p.role='driver' AND p.workflow_role='driver'
 AND coalesce(l.recorded_at,l.updated_at)<=clock_timestamp()+interval '5 seconds'
 ORDER BY l.updated_at DESC LIMIT 500;
END $$;
REVOKE ALL ON FUNCTION public.dlv_update_location_v2(double precision,double precision,real,timestamptz),public.dlv_map_locations(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_update_location_v2(double precision,double precision,real,timestamptz),public.dlv_map_locations(integer) TO authenticated;
NOTIFY pgrst,'reload schema';
