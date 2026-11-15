CREATE FUNCTION public.dlv_complaint_inbox_v2(p_branch integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 WITH inbox AS MATERIALIZED (SELECT * FROM public.dlv_complaint_inbox(p_branch)),
 counts AS (SELECT * FROM public.dlv_repeat_complaint_counts(ARRAY(SELECT id FROM inbox)))
 SELECT coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('repeat_count',coalesce(c.complaint_count,0)) ORDER BY i.created_at DESC,i.id DESC),'[]'::jsonb)
 FROM inbox i LEFT JOIN counts c ON c.incident_id=i.id;
$$;
REVOKE ALL ON FUNCTION public.dlv_complaint_inbox_v2(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_complaint_inbox_v2(integer) TO authenticated;
NOTIFY pgrst,'reload schema';
