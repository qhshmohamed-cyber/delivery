# Your Staff Delivery: No-cost recovery and externally controlled issues (2026-11-19)

## Already applied in Supabase
- Daily report archive runs at **05:05 Africa/Cairo**.
- Final close is scheduled at **05:15 and 05:35** with DST-aware local-time checks. It retries missing daily archival, and refuses to close a branch while that day has unfinished orders or lacks a report.
- Tested with four branches inside a full BEGIN/ROLLBACK database transaction; no real closing during testing. Cron is active, but its first real execution has not yet been observed.
- System owner health RPC: public.dlv_owner_operational_health(), requires active authenticated owner and unlocked individual PIN. It returns last-day close/archive status, cron run status, and GPS freshness, with no customer data or coordinates.
- The existing optional browser upgrade script now includes a manual owner "فحص الآن" control. **GitHub merge is not a TackHost live deployment.**

## ModSecurity PCRE limit: code-only mitigation
TackHost logs show repeated PCRE limit errors in response-side rules from RESPONSE-951-DATA-LEAKAGES-SQL.conf on /index.html, but HTTPS currently works. We cannot directly edit host-wide WAF rules or deployed files with the connected TackHost tools.

GitHub's tools/prepare_live_index_modularization.py is a staging-only, no-cost alternative that reduces the oversized HTML response by extracting one large inline JavaScript block without changing its contents. It uses the **ACTUAL LIVE** TackHost index, never GitHub's older index.

1. Preserve a new live backup outside public_html. Make sure all other live JS/assets remain available.
2. Run Python 3 standard library: python tools/prepare_live_index_modularization.py --source /path/to/current/public_html/index.html --out /path/to/private/new-staging-directory
3. The script leaves the original untouched and generates a reversible candidate index, a SHA256-hash-named JS file, and a manifest under a separate private staging folder. It refuses ambiguous/unsafe script contexts and output under the webroot.
4. Try the candidate on TackHost Test only. Verify successful JS asset HTTP 200 and MIME, login, manager/driver operation, customer privacy, browser console, PWA service-worker **offline caching**, and real GPS.
5. Compare ModSecurity logs before/after. Only deploy following full tests and a restore path. Extraction is a potential mitigation, **not a verified WAF fix**.

If the error remains, TackHost admins must adjust PCRE limits or consider a narrowly scoped exception for the affected **response-side** rule(s) on /index.html, without disabling ModSecurity or other request-side protections. This cannot be done through the current connector.

## Driver GPS: diagnosis without pretending tracking works
At last inspection branch 1 had three old GPS samples and no sample younger than one minute. This could be normal if drivers are not on duty or phone permissions/background execution are restricted. The current GitHub manager-map upgrade hides samples older than five minutes and visually distinguishes recent vs live. A real driver-phone test and two simultaneous customer links are still required; never invent location or bypass user permissions.

## Independent Supabase DB backup: not yet solved
TackHost's only visible backup (2026-11-16) does not include remote Supabase data. Backup/test tables inside Supabase are not independent disaster-recovery copies. Available connectors cannot produce and validate an encrypted off-site pg_dump with trusted DB credentials. Do not create paid branches or transfer customer/employee data to GitHub.

Use the supported Supabase dashboard export or an authenticated pg_dump from a trusted machine, store the encrypted result outside GitHub and Supabase, and perform a restore test in an isolated PostgreSQL environment. Until this happens, full recovery remains **unverified**.

## Safety
- Never replace production TackHost index.html from stale GitHub main.
- Maintain 90-day archived-order retention (longer if law/accounting requires it).
- Do not delete active orders, archived reports, audit trail or backups as part of performance tuning.
- No new paid services, SDKs, dependencies or direct production HTML replacement were introduced here.
