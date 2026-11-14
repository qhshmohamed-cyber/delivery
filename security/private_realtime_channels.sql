-- Postgres Changes remain governed by table RLS. Channels are private and receive-only.
CREATE OR REPLACE FUNCTION public.dlv_realtime_topic_allowed(p_topic text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT public.dlv_session_valid() AND (
 p_topic='profile:user:'||(SELECT auth.uid())::text
 OR (public.dlv_role() IS NOT NULL AND (
   p_topic='orders:user:'||(SELECT auth.uid())::text
   OR (p_topic='owner:user:'||(SELECT auth.uid())::text AND public.dlv_role()='admin' AND public.dlv_owner_page_check())
   OR EXISTS(SELECT 1 FROM public.dlv_branches b WHERE p_topic='brand:company:'||b.company_id::text AND public.dlv_can_access_branch(b.id))
 )));
$$;
REVOKE ALL ON FUNCTION public.dlv_realtime_topic_allowed(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_realtime_topic_allowed(text) TO authenticated,service_role;
CREATE POLICY dlv_private_channel_receive ON realtime.messages FOR SELECT TO authenticated
 USING (extension='broadcast' AND (SELECT public.dlv_realtime_topic_allowed(realtime.topic())));
CREATE POLICY dlv_private_channel_boundary ON realtime.messages AS RESTRICTIVE FOR ALL TO authenticated
 USING ((SELECT public.dlv_realtime_topic_allowed(realtime.topic()))) WITH CHECK (false);
NOTIFY pgrst,'reload schema';
