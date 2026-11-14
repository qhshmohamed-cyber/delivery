-- Your Staff Delivery billing readiness: read-only SQL. No customer/order mutations.
WITH function_security AS (
 SELECT p.proname, p.prosecdef, has_function_privilege('anon',p.oid,'EXECUTE') anon_exec,
 has_function_privilege('authenticated',p.oid,'EXECUTE') auth_exec,
 pg_get_functiondef(p.oid) body
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN (
 'dlv_owner_register_company','dlv_owner_billing_list','dlv_owner_billing_save',
 'dlv_owner_set_company_active','dlv_owner_billing_history')
), checks AS (
 SELECT 'billing_table_denies_anonymous' name,
 NOT has_table_privilege('anon','public.dlv_company_subscriptions','SELECT') ok
 UNION ALL SELECT 'billing_table_denies_direct_authenticated',
 NOT has_table_privilege('authenticated','public.dlv_company_subscriptions','SELECT')
 UNION ALL SELECT 'billing_audit_denies_anonymous',
 NOT has_table_privilege('anon','public.dlv_company_billing_audit','SELECT')
 UNION ALL SELECT 'owner_functions_deny_anonymous',
 (SELECT count(*)=5 AND bool_and(NOT anon_exec) FROM function_security)
 UNION ALL SELECT 'owner_functions_use_role_guard',
 (SELECT count(*)=5 AND bool_and(body LIKE '%auth.uid()%' AND (body LIKE '%admin%' OR body LIKE '%dlv_role()%')) FROM function_security)
 UNION ALL SELECT 'billing_changes_audited',
 (SELECT body LIKE '%dlv_company_billing_audit%' FROM function_security WHERE proname='dlv_owner_billing_save')
 UNION ALL SELECT 'company_suspension_audited',
 (SELECT body LIKE '%dlv_company_billing_audit%' FROM function_security WHERE proname='dlv_owner_set_company_active')
 UNION ALL SELECT 'company_suspension_non_destructive_sql',
 (SELECT body NOT ILIKE '%delete from%' AND body NOT ILIKE '%truncate %' FROM function_security WHERE proname='dlv_owner_set_company_active')
)
SELECT name, CASE WHEN ok THEN 'PASS' ELSE 'BLOCKED' END status FROM checks ORDER BY name;

-- NOT COVERED: real account authorization, billing payment processing,
-- expiry scheduling, backup restore, staging suspension/reactivation, mobile GPS.
