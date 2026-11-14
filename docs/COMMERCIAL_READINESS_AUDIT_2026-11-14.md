# Your Staff Delivery — Commercial Readiness Audit (2026-11-14)

## Verified
- Supabase project `mkptmejkcemdhlhdaort` reports ACTIVE_HEALTHY.
- GitHub main contains driver/order UI, complaints officer inbox, GPS functions, and WhatsApp action.
- `dlv_complaint_inbox` is SECURITY DEFINER, executable by authenticated but not anon, and checks role and branch access.
- Public tracking `dlv_track` accepts an eight-character code, rate-limits attempts, checks active company and branch, and returns no pilot phone.
- Public `dlv_customer_track` requires order number and eight-digit access code with hashed comparison and lockout.
- Public rating `dlv_submit_customer_rating` requires valid tracking code, delivered order, seven-day window, and rate limits.
- Security advisor reported 30 RLS-enabled tables without direct policies, including intentionally private tables; no policies must be added blindly.
- Performance advisor reported 22 unindexed foreign keys.

## Release blockers — not yet verified
1. Run multi-tenant negative tests using two isolated test companies: cross-company order, branch, driver, complaint, and billing access must all fail.
2. Test all roles: owner, manager, call center follow-up, kitchen, supervisor, driver, complaints officer.
3. Test customer complaints from tracking page and call center; confirm inbox visibility, WhatsApp access from linked order, audit trail.
4. Test GPS with an actual Android driver and manager map, including screen sleep, permissions, weak signal, stale readings, and sign-out.
5. Verify subscription suspension/reinstatement is reversible and does not delete employees, orders, or audit history.
6. Verify backups and perform a documented restore rehearsal in a nonproduction environment.
7. Review grants, security definer functions, RLS, audit logs, and exposed API keys.
8. Verify static hosting deployments, cache invalidation, HTTPS, privacy policy, and operational monitoring.
9. Load-test realistic concurrent orders, drivers, and multiple tenants without production customer data.
10. Confirm hosting/free-plan usage caps and commercial terms; no guarantee of permanently free production operation.

## Safe approach
- Do not use production customer records as test fixtures.
- Do not relax RLS or open tables simply to clear lint warnings.
- Keep migrations and role changes reviewed, reversible, and tested in staging.
- Do not advertise the platform as security-certified or 100% secure.
