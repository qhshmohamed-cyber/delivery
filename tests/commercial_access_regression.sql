-- Production-safe read-only commercial access checks.
-- Never insert or alter real users/orders to manufacture a passing result.
WITH checks AS (
 SELECT 'anonymous_orders_denied' name, NOT has_table_privilege('anon','public.dlv_orders','SELECT') ok
 UNION ALL SELECT 'anonymous_profiles_denied', NOT has_table_privilege('anon','public.dlv_profiles','SELECT')
 UNION ALL SELECT 'anonymous_locations_denied', NOT has_table_privilege('anon','public.dlv_locations','SELECT')
 UNION ALL SELECT 'anonymous_incidents_denied', NOT has_table_privilege('anon','public.dlv_incidents','SELECT')
 UNION ALL SELECT 'anonymous_subscriptions_denied', NOT has_table_privilege('anon','public.dlv_company_subscriptions','SELECT')
 UNION ALL SELECT 'authenticated_billing_direct_denied', NOT has_table_privilege('authenticated','public.dlv_company_subscriptions','SELECT')
 UNION ALL SELECT 'authenticated_companies_direct_denied', NOT has_table_privilege('authenticated','public.dlv_companies','SELECT')
 UNION ALL SELECT 'two_tenants_have_active_accounts', (SELECT count(*) >= 2 FROM (SELECT b.company_id FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id WHERE p.active AND p.role <> 'admin' GROUP BY b.company_id) t)
)
SELECT name,CASE WHEN ok THEN 'PASS' ELSE 'BLOCKED' END status FROM checks ORDER BY name;

-- Mandatory manual launch gates, not proved by SQL:
-- [ ] two different tenant accounts test forbidden order/profile/location/complaint access
-- [ ] supervisor/driver dispatch and GPS tests on physical phones
-- [ ] reversible company suspension and resumption in staging
-- [ ] staging backup restore, payment, load, and security tests
