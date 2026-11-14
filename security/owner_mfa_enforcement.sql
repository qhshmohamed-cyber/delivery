-- Apply only after index.html calls ownerMfaGate before ownerPageGate.
CREATE OR REPLACE FUNCTION public.dlv_owner_page_check()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT public.dlv_session_valid() AND auth.jwt()->>'aal'='aal2'
 AND EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=(SELECT auth.uid()) AND p.active AND p.role='admin' AND p.workflow_role='admin')
 AND (EXISTS(SELECT 1 FROM public.dlv_owner_page_unlocks u WHERE u.user_id=(SELECT auth.uid()) AND u.session_id=auth.jwt()->>'session_id' AND u.expires_at>now())
 OR NOT EXISTS(SELECT 1 FROM public.dlv_owner_page_security p WHERE p.user_id=(SELECT auth.uid())));
$$;
DO $patch$
DECLARE f record; definition text;
BEGIN
 FOR f IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('dlv_owner_page_status','dlv_owner_page_unlock','dlv_owner_page_set_password')
 LOOP
  definition:=pg_get_functiondef(f.oid);
  definition:=regexp_replace(definition,'\mBEGIN\M',E'BEGIN\n IF auth.jwt()->>''aal'' IS DISTINCT FROM ''aal2'' THEN RAISE EXCEPTION ''Owner MFA required'' USING ERRCODE=''42501''; END IF;\n','i');
  EXECUTE definition;
 END LOOP;
END $patch$;
NOTIFY pgrst, 'reload schema';
