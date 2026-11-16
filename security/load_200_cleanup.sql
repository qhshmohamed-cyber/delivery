-- Exact, disposable fixture tag. Never broaden these predicates to real data.
BEGIN;
CREATE TEMP TABLE qa200_users AS SELECT id FROM auth.users WHERE email LIKE 'qa200-20261116-c6d9-%@example.invalid';
CREATE TEMP TABLE qa200_companies AS SELECT id FROM public.dlv_companies WHERE slug IN ('qa200-20261116-c6d9-1','qa200-20261116-c6d9-2');
CREATE TEMP TABLE qa200_branches AS SELECT id FROM public.dlv_branches WHERE company_id IN(SELECT id FROM qa200_companies);
CREATE TEMP TABLE qa200_orders AS SELECT id FROM public.dlv_orders WHERE branch_id IN(SELECT id FROM qa200_branches);
DELETE FROM auth.sessions WHERE user_id IN(SELECT id FROM qa200_users);
DELETE FROM private.dlv_team_messages WHERE sender_id IN(SELECT id FROM qa200_users) OR recipient_id IN(SELECT id FROM qa200_users);
DELETE FROM private.dlv_driver_duty WHERE user_id IN(SELECT id FROM qa200_users);
DELETE FROM public.dlv_customer_message_consents WHERE order_id IN(SELECT id FROM qa200_orders);
DELETE FROM public.dlv_events WHERE order_id IN(SELECT id FROM qa200_orders);
DELETE FROM public.dlv_incidents WHERE branch_id IN(SELECT id FROM qa200_branches);
DELETE FROM public.dlv_orders WHERE id IN(SELECT id FROM qa200_orders);
DELETE FROM public.dlv_locations WHERE driver_id IN(SELECT id FROM qa200_users);
DELETE FROM public.dlv_callcenter_staff WHERE branch_id IN(SELECT id FROM qa200_branches);
DELETE FROM public.dlv_profiles WHERE user_id IN(SELECT id FROM qa200_users);
DELETE FROM auth.users WHERE id IN(SELECT id FROM qa200_users);
DELETE FROM private.dlv_feedback_forms WHERE company_id IN(SELECT id FROM qa200_companies);
DELETE FROM public.dlv_branch_sla WHERE branch_id IN(SELECT id FROM qa200_branches);
DELETE FROM public.dlv_branches WHERE id IN(SELECT id FROM qa200_branches);
DELETE FROM public.dlv_company_billing_audit WHERE company_id IN(SELECT id FROM qa200_companies);
DELETE FROM public.dlv_company_subscriptions WHERE company_id IN(SELECT id FROM qa200_companies);
DELETE FROM public.dlv_companies WHERE id IN(SELECT id FROM qa200_companies);
SELECT (SELECT count(*) FROM auth.users WHERE email LIKE 'qa200-20261116-c6d9-%@example.invalid') remaining_test_users,
 (SELECT count(*) FROM public.dlv_companies WHERE slug IN ('qa200-20261116-c6d9-1','qa200-20261116-c6d9-2')) remaining_test_companies,
 (SELECT count(*) FROM public.dlv_branches WHERE id IN(SELECT id FROM qa200_branches)) remaining_test_branches,
 (SELECT count(*) FROM public.dlv_orders WHERE id IN(SELECT id FROM qa200_orders)) remaining_test_orders;
COMMIT;
