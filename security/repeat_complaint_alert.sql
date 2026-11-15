CREATE FUNCTION private.dlv_normalized_contact_phone(p_phone text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE p text:=regexp_replace(translate(coalesce(p_phone,''),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),'[^0-9]','','g');
BEGIN
 IF p LIKE '00%' THEN p:=substring(p FROM 3);END IF;
 IF p ~ '^01[0125][0-9]{8}$' THEN p:='20'||substring(p FROM 2);END IF;
 IF p !~ '^[1-9][0-9]{7,14}$' THEN RETURN NULL;END IF;
 RETURN p;
END $$;
REVOKE ALL ON FUNCTION private.dlv_normalized_contact_phone(text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.dlv_repeat_complaint_counts(p_incidents bigint[])
RETURNS TABLE(incident_id bigint,complaint_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_role text:=public.dlv_role();
BEGIN
 IF NOT public.dlv_session_valid() OR auth.uid() IS NULL OR coalesce(v_role,'') NOT IN ('admin','manager','complaints_officer') THEN RAISE EXCEPTION 'غير مصرح' USING ERRCODE='42501';END IF;
 IF v_role='admin' AND NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'تحقق المالك مطلوب' USING ERRCODE='42501';END IF;
 IF p_incidents IS NULL OR cardinality(p_incidents)>300 THEN RAISE EXCEPTION 'قائمة شكاوى غير صالحة' USING ERRCODE='22023';END IF;
 RETURN QUERY
 WITH permitted AS MATERIALIZED (
  SELECT i.id,b.company_id,private.dlv_normalized_contact_phone(coalesce(s.customer_phone,o.phone)) phone
  FROM public.dlv_incidents i JOIN public.dlv_branches b ON b.id=i.branch_id AND b.active
  JOIN public.dlv_companies c ON c.id=b.company_id AND c.active AND c.onboarding_status='active'
  LEFT JOIN private.dlv_feedback_submissions s ON s.incident_id=i.id
  LEFT JOIN public.dlv_orders o ON o.id=i.order_id AND o.branch_id=i.branch_id
  WHERE i.category='customer_complaint' AND coalesce(s.kind,'complaint')='complaint' AND public.dlv_can_access_branch(i.branch_id)
 ), totals AS (SELECT company_id,phone,count(*) n FROM permitted WHERE phone IS NOT NULL GROUP BY company_id,phone)
 SELECT a.id,t.n FROM permitted a JOIN totals t ON t.company_id=a.company_id AND t.phone=a.phone WHERE a.id=ANY(p_incidents);
END $$;
REVOKE ALL ON FUNCTION public.dlv_repeat_complaint_counts(bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_repeat_complaint_counts(bigint[]) TO authenticated;
NOTIFY pgrst,'reload schema';
