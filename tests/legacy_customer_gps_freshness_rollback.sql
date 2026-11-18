-- Non-destructive regression verification for GPS privacy on both public tracking RPCs.
-- Run as a single transaction; rejects malformed tracking codes; no real orders changed.
BEGIN;
DO $test$
DECLARE
  legacy text:=pg_get_functiondef('public.dlv_customer_track(text,text)'::regprocedure);
  current_rpc text:=pg_get_functiondef('public.dlv_track(text)'::regprocedure);
  legacy_response jsonb;
  current_response jsonb;
BEGIN
  IF position('private.dlv_driver_active_navigation' IN legacy)=0 OR
     position('private.dlv_driver_active_navigation' IN current_rpc)=0 THEN
    RAISE EXCEPTION 'Per-order navigation gate missing'; END IF;
  IF position('and accuracy between 0 and 150' IN legacy)=0 OR
     position('and accuracy between 0 and 150' IN current_rpc)=0 THEN
    RAISE EXCEPTION 'GPS accuracy check missing'; END IF;
  IF position('and updated_at > clock_timestamp() - interval ''1 minute''' IN legacy)=0 OR
     position('and updated_at>clock_timestamp()-interval ''1 minute''' IN current_rpc)=0 THEN
    RAISE EXCEPTION 'GPS freshness check missing'; END IF;
  IF position('coalesce(recorded_at,updated_at) into v_lat,v_lng,v_location_updated' IN legacy)=0 THEN
    RAISE EXCEPTION 'Client-facing GPS timestamp is not sample time'; END IF;
  legacy_response:=public.dlv_customer_track('QA-NOT-AN-ORDER','00000000');
  IF legacy_response->>'error' IS NULL OR legacy_response->>'driver_location' IS NOT NULL THEN
    RAISE EXCEPTION 'Legacy customer validation leaked location'; END IF;
  current_response:=public.dlv_track('BAD')::jsonb;
  IF coalesce((current_response->>'found')::boolean,false) OR
     current_response->>'lat' IS NOT NULL OR current_response->>'lng' IS NOT NULL OR
     current_response->>'pilot_phone' IS NOT NULL THEN
    RAISE EXCEPTION 'Public tracking invalid-code rejection failed'; END IF;
  IF has_function_privilege('anon','public.dlv_begin_customer_navigation(bigint)','EXECUTE') OR
     has_function_privilege('anon','public.dlv_current_customer_navigation()','EXECUTE') OR
     has_function_privilege('anon','public.dlv_stop_customer_navigation(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'Unauthenticated caller can control driver navigation'; END IF;
END $test$;
ROLLBACK;

-- Real moving-phone / two-client acceptance cannot be replaced by this SQL test.
