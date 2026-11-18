# Your Staff Delivery — Production readiness gates (19 November 2026)

## Verified facts (live, read-only)
- TackHost domain `yourstaffdelivery.online`: HTTP 200, Let's Encrypt TLS, DNS resolving, latest health check ~60 ms **server response** (not browser speed or load capacity).
- Hosting disk: ~54 MB / 10,240 MB, ~0.5%. Do **not** delete operational files for space.
- PostgreSQL public application tables lacking RLS: **0**.
- One active primary owner; root-only secondary-owner RPCs reject anonymous access.
- Legacy `dlv_owner_add_branch` now requires a valid owner session and separate owner PIN unlock. Patch applied and independently checked in production.
- Daily report archive job active, 17 archived reports. Lightweight expired-session/rate-limit cleanup job active.
- **No final-close job** and **0 finalized day records**: this blocks certification of fully automatic day closing. The archive alone is not a completed close.
- Public SECURITY DEFINER warnings for track, ratings and QR feedback are **expected public APIs**. Evaluate scope and rate-limiting individually; never revoke indiscriminately.
- `test_archive_20261116` still occupies ~2 MB; do not delete until an independent tested Supabase DB backup exists.

## Release blockers — do not declare high-scale production-ready before these are resolved
1. **Independent encrypted backup and verified restore.** TackHost site backups do not back up Supabase data. The Supabase Free plan does not provide automatic daily downloadable backups. Use a secured, controlled, off-site SQL export and prove restore before changing retention or purging anything. Never store SQL exports, DB credentials or keys in this GitHub repository or `public_html`.
2. **Safe 05:00 operational close**: preserve open orders on a separate carry-over queue; guarantee one report per branch/day, idempotency and no accidental close while unfinished orders exist. Only enable automatic final close after validated tests and recovery plan.
3. **Real-device GPS/privacy acceptance**: one driver, multiple orders, two different customer tracking links, manager vs supervisor, branch isolation, denied GPS permission and stale-position behavior. Public clients must only see the location when the driver specifically navigates to *their order*.
4. **Order creation idempotency and offline recovery**: clients must know whether the save was confirmed; retries must not produce duplicates. Test Wi-Fi/mobile data toggles and app background/foreground.
5. **Staging load/soak test**: use an isolated environment, not synthetic orders on production. Validate realistic orders/roles, server error budgets, Realtime reconnection, and resource usage before making capacity claims.
6. **Live deployment parity and rollback**: live TackHost `index.html` is newer than GitHub `index.html`. Never deploy old GitHub HTML over it. Back up live assets before any additive script, verify exact old/new diff and restore procedure.
7. **ModSecurity diagnostics**: historical TackHost logs recorded PCRE limit errors for scanning very large `index.html`. Ask hosting provider to tune the specific failing rule rather than disabling firewall globally. Measure page load on actual staff phones.
8. **Protect operator accounts**: turn on MFA for Supabase and GitHub admin accounts, separate per-owner credentials, enable notifications for role changes and session revocations. Do not share owner passwords or unlock PINs.
9. **Data retention safeguards**: hide old orders from daily screens; only purge detailed records after 90 days when reports exist, retention obligations are met, and a restore has been tested. Do not delete audit logs or sensitive evidence automatically without an approved policy.
10. **Payment and provider limits**: do not enable Pro-only features, paid branching or new hosting without explicit approval. `leaked password protection` is a Pro+ feature; maintain strong password policy and rate limiting within the current tier.

## Re-run checks
Execute `tests/prelaunch_readonly_gate_20261119.sql` against production with a trusted DB admin. It performs **no writes** and clearly reports PASS/BLOCK/MANUAL.

At 2026-11-19 the baseline was:
- PASS: RLS on public tables, root-owner protected, report archiving, light maintenance, no unfinished active orders during the check.
- BLOCK: automated *final* day close is not configured and no final closes have occurred.
- MANUAL: tested encrypted off-site backup/restore, real GPS flow, network recovery, realistic peak load.

Keep the separate rollback procedure for each deployment. Never equate `HTTP 200` with a successful real-world load test.

## References
- Supabase production readiness: https://supabase.com/docs/guides/deployment/going-into-prod
- Supabase backup policy: https://supabase.com/docs/guides/platform/backups
- Supabase password controls: https://supabase.com/docs/guides/auth/password-security
- Supabase linter, public definer RPCs: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
