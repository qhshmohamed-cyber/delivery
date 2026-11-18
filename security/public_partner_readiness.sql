-- Public showcase must follow operational readiness, including later suspensions.
CREATE OR REPLACE FUNCTION public.dlv_sync_public_partner()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public,pg_temp AS $$
DECLARE v_company_id bigint;
BEGIN
 IF TG_TABLE_SCHEMA <> 'public' THEN RAISE EXCEPTION 'Unexpected partner sync schema'; END IF;
 IF TG_TABLE_NAME='dlv_companies' THEN v_company_id:=NEW.id;
 ELSIF TG_TABLE_NAME='dlv_company_branding' THEN v_company_id:=NEW.company_id;
 ELSE RAISE EXCEPTION 'Unexpected partner sync source'; END IF;
 INSERT INTO public.dlv_public_partners(company_id,display_name,logo_url,is_published)
 SELECT c.id,c.name,b.logo_url,coalesce(c.active AND c.onboarding_status='active',false)
 FROM public.dlv_companies c LEFT JOIN public.dlv_company_branding b ON b.company_id=c.id
 WHERE c.id=v_company_id
 ON CONFLICT(company_id) DO UPDATE SET display_name=excluded.display_name,
 logo_url=excluded.logo_url,is_published=excluded.is_published;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.dlv_sync_public_partner() FROM PUBLIC,anon,authenticated;
UPDATE public.dlv_public_partners p
SET is_published=coalesce(c.active AND c.onboarding_status='active',false)
FROM public.dlv_companies c WHERE c.id=p.company_id;
