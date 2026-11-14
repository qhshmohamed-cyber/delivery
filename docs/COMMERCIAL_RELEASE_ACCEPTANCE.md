# Commercial release acceptance — evidence-based gate

**Current state: NOT CERTIFIED.** Do not describe the product as security-certified or fully commercially ready.

## Confirmed on production (read-only)
- Anonymous direct SELECT denied on orders, profiles, locations, incidents and billing tables.
- Authenticated PostgreSQL role without an auth.uid() sees zero rows in orders, profiles, locations and incidents (2026-11-14).
- Static billing/owner permission tests passed; no live suspension or billing transaction executed.
- Supabase performance advisor lists 22 unindexed foreign keys; evaluate with query plans before adding indexes.

## Required acceptance evidence (not yet available)
1. **Tenant isolation**: provision two separate test-company identities in isolated staging; test role-by-role order, customer, GPS, complaint, billing and branch access; collect request/response status codes with PII redacted.
2. **Dispatch**: start driver shift explicitly, assign only by supervisor, verify driver only sees assigned orders, test completed and cancelled orders.
3. **GPS**: test Android and iOS foreground, screen locked, permission denied, permission restored, weak signal and stale location; document limitations of browser/PWA background tracking.
4. **Subscription**: in staging, suspend tenant, confirm all tenant staff lose access while platform owner retains administrative access, reactivate and compare counts and checksums; verify no deletions.
5. **Backup/restore**: restore staging from a sanitized backup, compare schema, row counts and referential integrity; never restore over production.
6. **Performance**: test realistic concurrent sessions and order writes on staging, report p95 latency and error rate, fix bottlenecks before approval.
7. **Operations**: review WhatsApp Meta integration, privacy/retention policies, support process, domain/HTTPS, incident response, hosting and backup costs and terms.
8. **CI**: confirm a completed successful GitHub Actions smoke run on the release commit. A workflow file alone is insufficient.

**Approval rule:** No commercial certification until every gate has dated evidence and a responsible approver. Never use real customer data as a staging fixture.
