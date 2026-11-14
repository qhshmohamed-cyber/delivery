# Your Staff Delivery — hosting and cost gate (2026-11-14)

## Observed production facts
- Supabase database size: 16 MB (16,676,531 bytes), 53 orders, 55 profiles. These are point-in-time observations, not a capacity forecast.
- Supabase Free currently lists 500 MB database per project, 50,000 monthly active users, 200 peak realtime connections, 2 million realtime messages per month, 5 GB uncached egress and 1 GB file storage. No automatic backups. Free projects may pause after a week of low activity.
- Supabase Free project count: 2 active projects across eligible organizations. Existing account has two active projects; a separate staging environment may require pausing an unused project, using local Supabase, or a paid plan. Do not modify other projects without approval.
- GitHub Pages currently hosts the frontend. GitHub's official limits explicitly prohibit using Pages as free web hosting for an online business or commercial SaaS. This is a **commercial release blocker**; move frontend to a host whose terms allow SaaS before selling.

## Sources
- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/billing-on-supabase
- https://supabase.com/docs/guides/platform/free-project-pausing
- https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits

## Release conditions
1. Choose commercially permitted hosting; configure HTTPS, domain, cache rules, rollback and deployment checks.
2. Test backup and restore to separate environment, including retention and recovery time.
3. Validate monthly bandwidth, database growth, realtime concurrency and message volume with actual workloads.
4. Confirm payment provider/WhatsApp charges and plan-specific terms separately; do not assume they are free.
5. Perform cross-tenant login, device GPS, order workflow and load tests before declaring production-ready.

**Current status: NOT CERTIFIED for commercial sale.** Internal evaluation is possible subject to limits and operational risk.
