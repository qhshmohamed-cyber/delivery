-- APPLY ONLY AFTER the CURRENT TackHost production code, Android web assets,
-- and Test have been upgraded with employee-session-guard.js.
-- Production preflight: owner can sign in concurrently from two devices,
-- first employee session works, second is rejected, logout releases the lease.
-- This replaces ONLY the existing auth validation function, not business data.
CREATE OR REPLACE FUNCTION public.dlv_session_valid()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
 SELECT EXISTS (
  SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
  JOIN public.dlv_profiles p ON p.user_id=u.id AND p.active
  WHERE s.id::text=auth.jwt()->>'session_id' AND s.user_id=(SELECT auth.uid())
  AND (s.not_after IS NULL OR s.not_after>now()) AND u.deleted_at IS NULL
  AND (u.banned_until IS NULL OR u.banned_until<=now())
  AND coalesce((auth.jwt()->>'exp')::bigint,0)>extract(epoch from now())
  AND public.dlv_staff_session_allowed()
 );
$function$;
REVOKE ALL ON FUNCTION public.dlv_session_valid() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_session_valid() TO authenticated,service_role;
