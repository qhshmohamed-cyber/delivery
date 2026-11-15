CREATE FUNCTION public.dlv_repeat_complaint_dashboard(p_branch integer DEFAULT NULL,p_company bigint DEFAULT NULL)
RETURNS TABLE(company_name text,branch_id integer,branch_name text,customer_phone text,total_count bigint,branch_count bigint,open_count bigint,last_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_role text:=public.dlv_role();
BEGIN
 IF NOT public.dlv_session_valid() OR auth.uid() IS NULL OR coalesce(v_role,'') NOT IN ('admin','manager') THEN RAISE EXCEPTION 'غير مصرح بلوحة المدير' USING ERRCODE='42501';END IF;
 IF v_role='admin' AND NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'تحقق المالك مطلوب' USING ERRCODE='42501';END IF;
 IF p_branch IS NOT NULL AND NOT public.dlv_can_access_branch(p_branch) THEN RAISE EXCEPTION 'فرع غير مصرح' USING ERRCODE='42501';END IF;
 RETURN QUERY WITH permitted AS MATERIALIZED (
  SELECT c.id company_id,c.name company,b.id branch,b.name branch_label,i.status,i.created_at,
   private.dlv_normalized_contact_phone(coalesce(s.customer_phone,o.phone)) phone
  FROM public.dlv_incidents i JOIN public.dlv_branches b ON b.id=i.branch_id AND b.active
  JOIN public.dlv_companies c ON c.id=b.company_id AND c.active AND c.onboarding_status='active'
  LEFT JOIN private.dlv_feedback_submissions s ON s.incident_id=i.id
  LEFT JOIN public.dlv_orders o ON o.id=i.order_id AND o.branch_id=i.branch_id
  WHERE i.category='customer_complaint' AND coalesce(s.kind,'complaint')='complaint'
  AND (p_company IS NULL OR c.id=p_company) AND public.dlv_can_access_branch(i.branch_id)
 ), totals AS (SELECT a.company_id,a.phone,count(*) n FROM permitted a WHERE a.phone IS NOT NULL GROUP BY a.company_id,a.phone HAVING count(*)>1)
 SELECT a.company,a.branch,a.branch_label,a.phone,t.n,count(*),count(*) FILTER(WHERE a.status IN ('open','in_progress')),max(a.created_at)
 FROM permitted a JOIN totals t ON t.company_id=a.company_id AND t.phone=a.phone
 WHERE p_branch IS NULL OR a.branch=p_branch
 GROUP BY a.company,a.branch,a.branch_label,a.phone,t.n ORDER BY max(a.created_at) DESC LIMIT 100;
END $$;
REVOKE ALL ON FUNCTION public.dlv_repeat_complaint_dashboard(integer,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_repeat_complaint_dashboard(integer,bigint) TO authenticated;
NOTIFY pgrst,'reload schema';
