-- Security hotfix deployed to production Supabase 2026-11-19.
-- Records the applied, idempotent, surgical change for source control.
-- Protects a LEGACY owner branch API; does not change the current company-scoped branch API.
DO $guard$
DECLARE
  definition text;
  old_guard text := ' if auth.uid() is null or public.dlv_role() is distinct from ''admin'' then raise exception ''للمالك فقط'';end if;';
  secure_guard text := ' if auth.uid() is null or NOT public.dlv_session_valid() or public.dlv_role() is distinct from ''admin'' or NOT public.dlv_owner_page_check() then raise exception ''Owner verification required'' using errcode=''42501'';end if;';
BEGIN
  SELECT pg_get_functiondef('public.dlv_owner_add_branch(text)'::regprocedure)
    INTO definition;
  IF position('NOT public.dlv_owner_page_check()' IN definition)>0 THEN
    RAISE NOTICE 'already protected';
    RETURN;
  END IF;
  IF definition IS NULL OR position(old_guard IN definition)=0
  OR (length(definition)-length(replace(definition,old_guard,'')))<>length(old_guard) THEN
    RAISE EXCEPTION 'Unexpected owner branch function; patch refused';
  END IF;
  EXECUTE replace(definition,old_guard,secure_guard);
END $guard$;
