CREATE OR REPLACE FUNCTION public.dlv_daily_branch_report(p_branch_id integer,p_day date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_role text; v_owner boolean; v_branch record; v_start timestamptz; v_end timestamptz; v_orders jsonb; v_staff jsonb; v_incidents jsonb;
BEGIN
 v_role:=public.dlv_role();
 v_owner:=v_role='admin' AND public.dlv_owner_page_check();
 SELECT b.id,b.name AS branch_name,c.name AS company_name INTO v_branch
 FROM public.dlv_branches b JOIN public.dlv_companies c ON c.id=b.company_id WHERE b.id=p_branch_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'branch unavailable' USING errcode='42501'; END IF;
 IF NOT v_owner THEN
  IF v_role IS DISTINCT FROM 'manager' OR p_day IS DISTINCT FROM public.dlv_operational_day(now())
   OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=auth.uid() AND p.active=true
    AND p.role='manager' AND p.workflow_role='manager' AND p.branch_id=p_branch_id)
  THEN RAISE EXCEPTION 'report access denied' USING errcode='42501'; END IF;
 END IF;
 IF p_day>public.dlv_operational_day(now()) THEN RAISE EXCEPTION 'future day denied' USING errcode='22023'; END IF;
 v_start:=(p_day::timestamp+interval '5 hours') AT TIME ZONE 'Africa/Cairo';
 v_end:=((p_day+1)::timestamp+interval '5 hours') AT TIME ZONE 'Africa/Cairo';
 SELECT jsonb_build_object('total',count(*),'delivered',count(*) FILTER (WHERE status='delivered'),
  'cancelled',count(*) FILTER (WHERE status='cancelled'),
  'failed',count(*) FILTER (WHERE status='failed'),
  'net_after_cancel',count(*) FILTER (WHERE status<>'cancelled'),
  'late_over_60m',count(*) FILTER (WHERE delivered_at IS NOT NULL AND received_at IS NOT NULL AND delivered_at-received_at>interval '60 minutes'))
 INTO v_orders FROM public.dlv_orders WHERE branch_id=p_branch_id AND created_at>=v_start AND created_at<v_end;
 SELECT coalesce(jsonb_agg(jsonb_build_object('employee',s.full_name,'orders',s.n) ORDER BY s.n DESC), '[]'::jsonb)
 INTO v_staff FROM (SELECT coalesce(cs.full_name,'غير محدد') full_name,count(*) n
  FROM public.dlv_orders o LEFT JOIN public.dlv_callcenter_staff cs ON cs.id=o.callcenter_staff_id AND cs.branch_id=o.branch_id
  WHERE o.branch_id=p_branch_id AND o.created_at>=v_start AND o.created_at<v_end
  GROUP BY cs.id,cs.full_name) s;
 SELECT jsonb_build_object('total',count(*),'open',count(*) FILTER (WHERE status NOT IN ('resolved','closed')),
  'items',coalesce(jsonb_agg(jsonb_build_object('category',category,'title',title,'status',status)), '[]'::jsonb))
 INTO v_incidents FROM public.dlv_incidents WHERE branch_id=p_branch_id AND created_at>=v_start AND created_at<v_end;
 RETURN jsonb_build_object('company',v_branch.company_name,'branch',v_branch.branch_name,'branch_id',p_branch_id,
  'day',p_day,'cutoff','05:00 Africa/Cairo','orders',v_orders,'staff',v_staff,'incidents',v_incidents,
  'generated_at',now());
END $$;
REVOKE ALL ON FUNCTION public.dlv_daily_branch_report(integer,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dlv_daily_branch_report(integer,date) TO authenticated;