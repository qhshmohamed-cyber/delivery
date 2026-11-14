-- READ-ONLY operational capacity snapshot for Supabase SQL editor.
-- Database size is not the same as billed disk usage or network egress.
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size,
 pg_database_size(current_database()) AS database_bytes,
 (SELECT count(*) FROM public.dlv_orders) AS order_rows,
 (SELECT count(*) FROM public.dlv_profiles) AS profile_rows,
 (SELECT count(*) FROM public.dlv_companies) AS company_rows,
 (SELECT count(*) FROM public.dlv_branches) AS branch_rows;
-- Review Supabase Dashboard > Usage for network egress, realtime messages,
-- active users and storage; SQL cannot accurately determine these billing metrics.
