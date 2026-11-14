CREATE OR REPLACE FUNCTION public.dlv_can_access_branch(p_branch integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_temp AS $$
 SELECT EXISTS(
 SELECT 1 FROM public.dlv_profiles p
 JOIN public.dlv_branches target ON target.id=p_branch AND target.active=true
 JOIN public.dlv_companies company ON company.id=target.company_id AND company.active=true AND company.onboarding_status='active'
 LEFT JOIN public.dlv_branches home ON home.id=p.branch_id
 WHERE p.user_id=(SELECT auth.uid()) AND p.active=true
 AND ((p.role='admin' AND p.workflow_role='admin' AND public.dlv_owner_page_check())
 OR (home.company_id=target.company_id AND (p.branch_id=p_branch OR p_branch=ANY(coalesce(p.allowed_branch_ids,'{}'::integer[])))))
 ) $$;
CREATE OR REPLACE FUNCTION public.dlv_my_branches()
RETURNS TABLE(id integer,name text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_temp AS $$
 SELECT DISTINCT b.id,b.name FROM public.dlv_profiles p
 JOIN public.dlv_branches home ON home.id=p.branch_id
 JOIN public.dlv_branches b ON b.company_id=home.company_id
 JOIN public.dlv_companies c ON c.id=b.company_id
 WHERE p.user_id=(SELECT auth.uid()) AND p.active=true
 AND b.active=true AND c.active=true AND c.onboarding_status='active'
 AND ((p.role='admin' AND p.workflow_role='admin' AND public.dlv_owner_page_check())
 OR b.id=p.branch_id OR b.id=ANY(coalesce(p.allowed_branch_ids,'{}'::integer[])))
 ORDER BY b.id $$;
REVOKE ALL ON FUNCTION public.dlv_can_access_branch(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dlv_can_access_branch(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.dlv_my_branches() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dlv_my_branches() TO authenticated;