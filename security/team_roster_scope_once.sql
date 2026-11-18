-- Resolve management scope once per request, rather than once per candidate row.
CREATE OR REPLACE FUNCTION public.dlv_team_members(p_search text DEFAULT '',p_offset integer DEFAULT 0,p_limit integer DEFAULT 100)
RETURNS TABLE(user_id uuid,full_name text,job_title text,branch_id integer,branch_name text,company_name text,last_seen timestamptz,online boolean,visible boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=(SELECT auth.uid());actor_role text:=public.dlv_role();allowed integer[];
BEGIN
 IF NOT public.dlv_session_valid() OR actor_role IS NULL OR actor_role NOT IN('admin','manager')
 OR (actor_role='admin' AND NOT public.dlv_owner_page_check()) THEN RAISE EXCEPTION 'Management only' USING ERRCODE='42501';END IF;
 IF actor_role='admin' THEN
 SELECT array_agg(b.id) INTO allowed FROM public.dlv_branches b JOIN public.dlv_companies c ON c.id=b.company_id WHERE b.active AND c.active AND c.onboarding_status='active';
 ELSE SELECT array_agg(b.id) INTO allowed FROM public.dlv_my_branches() b;END IF;
 RETURN QUERY SELECT p.user_id,p.full_name,coalesce(p.job_title,p.workflow_role),b.id,b.name,c.name,
 presence.last_seen,coalesce(presence.last_seen>now()-interval '90 seconds',false),coalesce(presence.visible,false)
 FROM public.dlv_profiles p JOIN auth.users u ON u.id=p.user_id JOIN public.dlv_branches b ON b.id=p.branch_id JOIN public.dlv_companies c ON c.id=b.company_id
 LEFT JOIN LATERAL(SELECT max(h.last_seen) AS last_seen,bool_or(h.visible AND h.last_seen>now()-interval '90 seconds') AS visible
 FROM private.dlv_team_presence h JOIN auth.sessions s ON s.id=h.session_id AND s.user_id=h.user_id
 WHERE h.user_id=p.user_id AND (s.not_after IS NULL OR s.not_after>now()))presence ON true
 WHERE p.active AND p.branch_id=ANY(coalesce(allowed,'{}'::integer[])) AND p.user_id<>actor
 AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now())
 AND (p.role<>'admin' OR actor_role='admin')
 AND (coalesce(btrim(p_search),'')='' OR position(lower(left(btrim(p_search),100)) IN lower(p.full_name||' '||b.name||' '||c.name))>0)
 ORDER BY (presence.last_seen>now()-interval '90 seconds') DESC NULLS LAST,p.full_name,p.user_id
 LIMIT least(greatest(coalesce(p_limit,100),1),100) OFFSET greatest(coalesce(p_offset,0),0);
END $$;
