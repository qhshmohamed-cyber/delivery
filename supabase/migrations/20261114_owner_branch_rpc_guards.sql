CREATE OR REPLACE FUNCTION public.dlv_list_branches()
RETURNS TABLE(id integer,name text,active boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR public.dlv_role() IS DISTINCT FROM 'admin' OR NOT public.dlv_owner_page_check() THEN
 RAISE EXCEPTION 'للمالك فقط' USING errcode='42501';
 END IF;
 RETURN QUERY SELECT b.id,b.name,b.active FROM public.dlv_branches b ORDER BY b.id;
END $$;
CREATE OR REPLACE FUNCTION public.dlv_list_branch_drivers(p_branch_id integer)
RETURNS TABLE(user_id uuid,full_name text,employee_code text,branch_id integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR p_branch_id IS NULL OR NOT public.dlv_can_access_branch(p_branch_id) THEN
 RAISE EXCEPTION 'غير مصرح بالوصول لهذا الفرع' USING errcode='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=auth.uid() AND p.active AND
 ((p.role='admin' AND p.workflow_role='admin' AND public.dlv_owner_page_check()) OR p.workflow_role IN ('manager','supervisor'))) THEN
 RAISE EXCEPTION 'غير مصرح بعرض الطيارين' USING errcode='42501';
 END IF;
 RETURN QUERY SELECT p.user_id,p.full_name,p.employee_code,p.branch_id FROM public.dlv_profiles p
 WHERE p.role='driver' AND p.workflow_role='driver' AND p.active AND p.branch_id=p_branch_id ORDER BY p.full_name;
END $$;