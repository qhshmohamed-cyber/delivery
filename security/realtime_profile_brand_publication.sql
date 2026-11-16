-- Preserve existing publication members and all existing RLS boundaries.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='dlv_profiles') THEN ALTER PUBLICATION supabase_realtime ADD TABLE public.dlv_profiles;END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='dlv_company_branding') THEN ALTER PUBLICATION supabase_realtime ADD TABLE public.dlv_company_branding;END IF;
END $$;
