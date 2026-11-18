-- Your Staff Delivery / 2026-11-18
-- Preserve existing tracking codes and navigation-target checks.
-- Align the legacy customer tracking RPC's GPS sample freshness/accuracy with dlv_track.
-- Applied on production Supabase 2026-11-18; this file records the exact idempotent patch.
-- Do NOT deploy an older index.html from GitHub onto TackHost.
DO $migration$
DECLARE
 v_definition text;
 v_old_select text := 'select lat,lng,updated_at into v_lat,v_lng,v_location_updated';
 v_new_select text := 'select lat,lng,coalesce(recorded_at,updated_at) into v_lat,v_lng,v_location_updated';
 v_old_filter text := 'and updated_at > now() - interval ''2 minutes'';';
 v_new_filter text := 'and updated_at > clock_timestamp() - interval ''1 minute''
      and coalesce(recorded_at,updated_at) > clock_timestamp() - interval ''1 minute''
      and coalesce(recorded_at,updated_at) <= clock_timestamp() + interval ''5 seconds''
      and accuracy between 0 and 150;';
BEGIN
 SELECT pg_get_functiondef('public.dlv_customer_track(text,text)'::regprocedure) INTO v_definition;
 IF strpos(v_definition,v_new_filter)>0 AND strpos(v_definition,v_new_select)>0 THEN
   RAISE NOTICE 'GPS freshness patch already present';
   RETURN;
 END IF;
 IF v_definition IS NULL OR strpos(v_definition,v_old_select)=0 OR strpos(v_definition,v_old_filter)=0 OR
    strpos(v_definition,'private.dlv_driver_active_navigation')=0
 THEN RAISE EXCEPTION 'Customer tracking function differs from audited version'; END IF;
 IF length(v_definition)-length(replace(v_definition,v_old_select,'')) <> length(v_old_select)
 OR length(v_definition)-length(replace(v_definition,v_old_filter,'')) <> length(v_old_filter)
 THEN RAISE EXCEPTION 'Ambiguous GPS patch occurrence count'; END IF;
 v_definition:=replace(v_definition,v_old_select,v_new_select);
 v_definition:=replace(v_definition,v_old_filter,v_new_filter);
 EXECUTE v_definition;
END
$migration$;