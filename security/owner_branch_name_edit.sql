CREATE OR REPLACE FUNCTION public.dlv_owner_rename_company_branch(p_company_id bigint,p_branch_id integer,p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE clean_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g'); old_name text;
BEGIN
 IF NOT public.dlv_session_valid() OR NOT public.dlv_owner_page_check()
 OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=(SELECT auth.uid()) AND active AND role='admin' AND workflow_role='admin')
 THEN RAISE EXCEPTION 'تعديل أسماء الفروع لمالك النظام بعد فتح قفل الصفحة فقط' USING ERRCODE='42501'; END IF;
 IF length(clean_name) NOT BETWEEN 3 AND 100 OR clean_name ~ '[[:cntrl:]]' THEN
 RAISE EXCEPTION 'اسم الفرع يجب أن يكون من 3 إلى 100 حرف' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM public.dlv_companies WHERE id=p_company_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة' USING ERRCODE='22023'; END IF;
 SELECT name INTO old_name FROM public.dlv_branches WHERE id=p_branch_id AND company_id=p_company_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'الفرع لا يتبع الشركة المحددة' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.dlv_branches WHERE company_id=p_company_id AND id<>p_branch_id AND lower(btrim(name))=lower(clean_name)) THEN
 RAISE EXCEPTION 'يوجد فرع آخر بالاسم نفسه داخل الشركة' USING ERRCODE='23505'; END IF;
 IF old_name IS DISTINCT FROM clean_name THEN
  UPDATE public.dlv_branches SET name=clean_name WHERE id=p_branch_id AND company_id=p_company_id;
  INSERT INTO public.dlv_security_audit(actor,branch_id,entity,entity_id,action,changes)
  VALUES(auth.uid(),p_branch_id,'dlv_branches',p_branch_id::text,'UPDATE',jsonb_build_object('company_id',p_company_id,'old_name',old_name,'new_name',clean_name));
 END IF;
 RETURN jsonb_build_object('id',p_branch_id,'company_id',p_company_id,'name',clean_name);
END;
$$;
REVOKE ALL ON FUNCTION public.dlv_owner_rename_company_branch(bigint,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_owner_rename_company_branch(bigint,integer,text) TO authenticated;
NOTIFY pgrst,'reload schema';
