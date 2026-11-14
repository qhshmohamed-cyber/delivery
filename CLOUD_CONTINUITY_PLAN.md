# Your Staff Delivery — Cloud continuity and migration plan
Updated: 2026-11-14

## Current production topology
- Frontend: GitHub Pages (temporary development deployment).
- Backend: Supabase project `mkptmejkcemdhlhdaort` (Free).
- Git source: `qhshmohamed-cyber/delivery`.
- Source snapshot: branch `backup-2026-11-14-security`.

## Constraints
- Supabase Free may pause for insufficient database activity over 7 days; genuine usage often helps but does not guarantee availability.
- GitHub Pages terms do not permit using it as a free hosting service for a commercial SaaS. Migrate the frontend before commercial launch.
- No free service guarantees perpetual 24/7 availability or unlimited traffic.
- Do NOT implement fake keepalive traffic as a substitute for a compliant hosting and backup strategy.

## Stage 1 — preserve existing service
- Keep current production URL and Supabase project unchanged during migration.
- Verify branch-level RLS, privileged RPCs, and anonymous customer-tracking controls.
- Enable provider email notifications and configure a genuine external uptime monitor; alerts are not automatic recovery.
- Keep owner-only administrative permissions; do not store secrets in repository or client.

## Stage 2 — full disaster recovery (required before migration)
1. Export PostgreSQL roles/schema/data, including auth and storage metadata, via supported secure backup tooling; validate coverage.
2. Export Storage objects separately; database dumps alone do not contain object bytes.
3. Inventory edge functions, auth provider configuration, email/SMTP settings, OAuth callbacks, realtime and webhooks, and environment variables. Never commit secrets.
4. Encrypt backups at rest and retain copies outside the hosting provider and outside the Git repository.
5. Test restore into an isolated project; validate sign-in, permissions, order lifecycle, tracking, storage, and realtime.
6. Record restore time, gaps and reconfiguration steps. Do not claim a full recovery kit until all checks pass.

## Stage 3 — compliant hosting
- Choose a host whose terms permit commercial SaaS and whose free quota covers expected traffic.
- Build from the pinned repository commit and deploy over HTTPS with real security headers.
- Configure a domain and tested DNS rollback before cutover.
- Validate production access by role, tenant isolation, customer tracking, Android client and WhatsApp integrations.
- Switch traffic only after successful acceptance tests.

## Stage 4 — continuity
- Monitor frontend HTTP and backend functional health without exposing customer data.
- Configure alert recipients, on-call response, and a written rollback plan.
- Schedule encrypted off-platform backups; routinely test restores.
- Track free quota and growth; plan a paid tier if business-critical reliability is required.

## Release gate
No migration, database deletion, key rotation, company suspension, or production cutover without verified backups and explicit approval.
