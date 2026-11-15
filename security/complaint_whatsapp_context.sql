CREATE FUNCTION public.dlv_complaint_whatsapp_context(p_incident bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_role text:=public.dlv_role();v_result jsonb;
BEGIN
 IF NOT public.dlv_session_valid() OR auth.uid() IS NULL OR coalesce(v_role,'') NOT IN ('admin','manager','complaints_officer') THEN RAISE EXCEPTION 'غير مصرح' USING ERRCODE='42501';END IF;
 IF v_role='admin' AND NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'تحقق المالك مطلوب' USING ERRCODE='42501';END IF;
 SELECT jsonb_build_object('company',c.name,'officer',p.full_name,'phone',coalesce(s.customer_phone,o.phone),'complaint_id',i.id)
 INTO v_result FROM public.dlv_incidents i
 JOIN public.dlv_branches b ON b.id=i.branch_id AND b.active
 JOIN public.dlv_companies c ON c.id=b.company_id AND c.active AND c.onboarding_status='active'
 JOIN public.dlv_profiles p ON p.user_id=auth.uid() AND p.active
 LEFT JOIN private.dlv_feedback_submissions s ON s.incident_id=i.id
 LEFT JOIN public.dlv_orders o ON o.id=i.order_id AND o.branch_id=i.branch_id
 WHERE i.id=p_incident AND i.category='customer_complaint' AND public.dlv_can_access_branch(i.branch_id);
 IF v_result IS NULL THEN RAISE EXCEPTION 'الشكوى غير متاحة لحسابك' USING ERRCODE='42501';END IF;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.dlv_complaint_whatsapp_context(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_complaint_whatsapp_context(bigint) TO authenticated;
NOTIFY pgrst,'reload schema';
