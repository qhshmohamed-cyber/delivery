# Safe data retention policy — proposal, NOT enabled

Requested operational rollover: **05:00 Africa/Cairo**. This should reset the owner daily-report *visibility* only, never delete manager history or order records.

## Candidate cleanup (after approval and tested backup)
- Read notifications older than 30 days: potential deletion candidate.
- Last-known GPS locations older than 30 days: potential deletion candidate only if driver is not on an active delivery, and stale-location diagnostics remain intact.
- Expired public rating rate-limit windows older than 7 days: potential deletion candidate after verifying the rate-limit implementation and abuse prevention.
- Never automatically delete orders, cancellations, customer complaints, workflow events, security audit trails, billing or payroll data.

## Production inspection (2026-11-14)
All three preview counts were zero; automatic deletion would reclaim no rows now. Total database footprint 16 MB. Database files do not necessarily shrink after DELETE; PostgreSQL may reuse free space internally and VACUUM is required to reclaim dead tuples. Deleting old rows is not a guaranteed way to stay within Supabase Free billing limits, particularly network/realtime usage.

## Conditions before scheduling
1. Verify an independent restorable backup (Supabase Free has no automated backups).
2. Verify retention obligations, customer privacy requirements and minimum audit retention.
3. Add bounded cleanup batches and idempotent logs, test on staging, set timezone Africa/Cairo and monitor.
4. Protect owner/manager reporting from source-row deletion; aggregate and preserve daily summaries before archiving.
5. Monitor Supabase Dashboard usage for database size, egress and realtime messages; schedule alert thresholds.

**Status: Preview-only. No cron or destructive cleanup enabled.**
