# Your Staff Delivery — Lightweight upgrade (2026-11-19)

## Status
- This commit adds **one opt-in browser script**. It does not edit, replace or auto-publish `index.html`.
- Production TackHost `public_html/index.html` has changes absent from GitHub `main`. **Never deploy GitHub's older HTML file over it**.
- Supabase backend RPCs referenced below were installed separately in production on 2026-11-18/19; this GitHub commit alone does **not** install or migrate them.

## Contents
`yourstaff-efficient-20261119.js` (<40 KB original JS, no new library dependency):
- Branded **horizontal** stage compliance/delay bars and hourly peak breakdown per selected branch, using `dlv_manager_stage_bars(p_branch,p_day)`; incomplete or invalid stage samples are not counted as compliant.
- Manager read-only GPS map using branch-scoped `dlv_map_locations(p_branch)`. Clearly differentiates fresh (<60 s), recent (<5 min) and invalid/stale GPS. It does not alter customer tracking restrictions or driver assignment.
- Shows logged-in owner's actual profile name in owner dashboard header.
- Root owner-only control for viewing, creating, promoting and deactivating a **secondary owner account**, via `dlv_root_owner_accounts`, `dlv_root_create_secondary_owner`, `dlv_root_promote_secondary_owner`, `dlv_root_toggle_secondary_owner`. Each owner needs an independent login and PIN; root access enforced **server-side**.

## Production installation — TackHost only
1. Save fresh **full** `public_html` backup outside web root AND independently back up the Supabase database. The TackHost site backup does not contain the Supabase database.
2. Upload **only** `yourstaff-efficient-20261119.js` to the live `public_html` root. Do not copy `index.html`, `sw.js`, or stale GitHub web assets.
3. In the CURRENT live `index.html` immediately before `</body>`, add **exactly one** script tag:
   ```html
   <script src="yourstaff-efficient-20261119.js?v=20261119-1"></script>
   ```
4. If the old `ys-brand-performance-20261118.js` tag exists, replace *only that tag* with this new tag. Keep every other existing script, including `repeat-complaints-review.js`.
5. Refresh the PWA, test one manager's company/branch/map and GPS freshness, the owner-branded dashboard, and the root-only management button. Confirm the logged-in root owner can list owners after PIN unlock.
6. **Do not create a second owner without naming the authorized recipient** and completing a logged-in root/PIN acceptance test. Test both owners independently in separate browsers, including disabling the secondary owner and verifying root remains active.

## Verification and limitations
Run `node tests/efficient_upgrade_smoke.test.cjs` (Node built-ins only) before deployment.
Browser syntax and defensive startup checks have passed locally. Authorization must be validated with live owner/manager accounts; a SQL check alone does not certify the account-creation workflow.
Real moving-device GPS tracking requires on-site validation. Roll back only the new script tag to reverse its browser UI effects.
No destructive cleanup of orders, closed-day reports, complaints, audit trails or backup schemas is included. A light Supabase cron handles *only expired transient access/session counters*.

## Scope and cost
- No additional subscription, dependency, build pipeline or GitHub Actions workflow.
- Changes are additive to GitHub and will **not** deploy automatically to TackHost.
- Production `index.html` must be treated as authoritative until it is explicitly reconciled with GitHub.

## Operational readiness: root/secondary owners
- The owner dashboard shows a compact `حالة التشغيل والأمان` card. Click `فحص الآن` to request `dlv_owner_operational_health()`; the endpoint requires an active authenticated owner session and the individual owner's PIN unlock. It has no automatic polling, secret export or persistent data storage.
- The response indicates per-branch archive/close status for the last completed Egypt operational day, the number of unfinished orders, current/last driver GPS signal and the status of four Supabase cron tasks. Zero GPS updates alone does not prove a fault when drivers are not on duty.
- Automatic closure retries at **05:15 and 05:35 Africa/Cairo**. It reattempts the **05:05 archival step** if needed and refuses to close branches with missing archive or unfinished orders. No order data is deleted by closing.
- Production GPS remains unverified until a driver's actual phone shares a new location; the GitHub JS assets are **not automatically published to TackHost**.
- A database backup independent of Supabase remains **unverified**; a TackHost web backup alone is insufficient.
