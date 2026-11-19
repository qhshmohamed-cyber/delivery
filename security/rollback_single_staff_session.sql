-- Return to previous valid-auth-session behavior, WITHOUT deleting session-lease data.
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
 );
$function$;
REVOKE ALL ON FUNCTION public.dlv_session_valid() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_session_valid() TO authenticated,service_role;
