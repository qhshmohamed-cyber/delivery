-- Your Staff Delivery: READ-ONLY prelaunch gate, 2026-11-19
-- No mutations or personal data returned. Run as a trusted DB admin.
-- PASS = verified condition; BLOCK = not production-ready; MANUAL = real-world test needed.
WITH s AS (
SELECT
 (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity) AS no_rls,
 (SELECT count(*) FROM public.dlv_profiles WHERE active AND role='admin' AND workflow_role='admin') AS owners,
 (SELECT count(*) FROM private.dlv_platform_root_owner) AS roots,
 (SELECT count(*) FROM cron.job WHERE active AND jobname='yourstaff_daily_reports_5am_cairo') AS archive_jobs,
 (SELECT count(*) FROM cron.job WHERE active AND command ILIKE '%dlv_close_day%') AS close_jobs,
 (SELECT count(*) FROM public.dlv_daily_report_archive) AS reports,
 (SELECT count(*) FROM private.dlv_day_close_control) AS closed_days,
 (SELECT count(*) FROM cron.job WHERE active AND jobname='dlv_light_housekeeping') AS cleanup_jobs,
 (SELECT count(*) FROM public.dlv_orders WHERE status NOT IN ('delivered','failed','cancelled')) AS pending_orders,
 (strpos(lower(pg_get_functiondef('public.dlv_owner_add_branch(text)'::regprocedure)), 'not public.dlv_owner_page_check()')>0) AS legacy_pin_guard,
 has_function_privilege('anon','public.dlv_root_create_secondary_owner(text,text,text,text,text)','EXECUTE') AS anon_owner_create,
 has_function_privilege('anon','public.dlv_root_toggle_secondary_owner(uuid,boolean,text)','EXECUTE') AS anon_owner_toggle
)
SELECT priority,gate,status,details FROM s CROSS JOIN LATERAL (VALUES
 (1,'RLS on all public tables',CASE WHEN no_rls=0 THEN 'PASS' ELSE 'BLOCK' END,'Tables without RLS: '||no_rls),
 (2,'Owner control',CASE WHEN owners BETWEEN 1 AND 2 AND roots=1 AND legacy_pin_guard AND NOT anon_owner_create AND NOT anon_owner_toggle THEN 'PASS' ELSE 'BLOCK' END,'Active owners: '||owners||'; primary owners: '||roots),
 (3,'Report archive',CASE WHEN archive_jobs=1 AND reports>0 THEN 'PASS' ELSE 'BLOCK' END,'Archiver jobs: '||archive_jobs||'; archived reports: '||reports),
 (4,'Final close safety',CASE WHEN close_jobs>0 AND closed_days>0 THEN 'PASS' ELSE 'BLOCK' END,'Final close jobs: '||close_jobs||'; days closed: '||closed_days),
 (5,'Expired transient cleanup',CASE WHEN cleanup_jobs=1 THEN 'PASS' ELSE 'BLOCK' END,'Cleanup jobs: '||cleanup_jobs),
 (6,'Unfinished orders',CASE WHEN pending_orders=0 THEN 'PASS' ELSE 'MANUAL' END,'Unfinished orders: '||pending_orders||'; never delete them to pass'),
 (7,'Independent encrypted DB backup and test restore','MANUAL','Must independently export Supabase, store it off-site and prove a restore. TackHost file backup is insufficient.'),
 (8,'Per-order real driver GPS / privacy','MANUAL','Verify different customer phones, driver navigation, stale location, branch isolation.'),
 (9,'Offline and duplicate-request recovery','MANUAL','Use real devices. Verify saved/failed states, retry deduplication and resubscription.'),
 (10,'Peak load and 5 AM rollover','MANUAL','Load test off-production first; inspect errors, response times and day handoff.')
) AS gates(priority,gate,status,details) ORDER BY priority;