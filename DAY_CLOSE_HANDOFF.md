# Your Staff Delivery — secure day close staging handoff (2026-11-17)

## Status
STAGING ONLY. Not production-ready. Do not replace the current TackHost index.html with GitHub main: the deployed file contains newer GPS, QR login, staff-entry, feedback-owner v2, and other changes absent from main.

## Supabase changes ALREADY APPLIED (project mkptmejkcemdhlhdaort)
- public.dlv_close_day(branch_id,day): owner session + owner-page verification, branch authorization, day cutoff at 05:00 Africa/Cairo, unfinished-order check, archive write, closed-day marker, repeat-call protection.
- private.dlv_guard_closed_day_order trigger on public.dlv_orders: rejects inserts for closed operational day, serializes inserts and closing by branch advisory lock.
- public.dlv_owner_day_close_status and public.dlv_owner_day_close_archive: owner-only status and archive listing. Anon execute revoked; authenticated execute is additionally authorized inside functions.
- Retention deadline recorded as day+90, no automatic deletion.
- Existing 05:00 report archive cron retained; archived report does NOT by itself mean day is closed.

## New staged file
- owner-day-close.js (this branch): owner dashboard widget; must only be mounted AFTER owner gate succeeds, with current authenticated Supabase client and validated branch ID.
- Suggested mount after owner page rendered:
  <script defer src="owner-day-close.js?v=20261117"></script>
  YourStaffDayClose.mount({root: ownerPanelElement, supabase: existingClient, branchId: selectedBranchId, ownerVerified: true});
  Replace placeholders using actual deployed identifiers; never assume the GitHub index is current.

## IMPORTANT: NOT YET DONE
- Integration into CURRENT deployed index.html and comparison against its private backup.
- End-to-end role tests with real authorized test accounts; multi-branch, concurrency, mobile, GPS, realtime, restore test.
- Closed-day filtering from all daily screens: do not ship without this, since old orders may still appear.
- Review remaining RLS and SECURITY DEFINER warnings individually, not broad permission revocations.
- Ensure the auto-archive cron's report-only behavior is intended and investigate historical unfinished orders.
- Full privacy audit of customer-facing pilot contact fields and frontend.
- Verify customer consent/legal accounting retention requirements before any automatic deletion.

## Support deployment protocol
1. Obtain current production index.html and all loaded assets, compare to backup and GitHub staged module.
2. Back up public_html and DB migration state.
3. Integrate only the new owner widget into CURRENT production code in Test; do not overwrite existing functionality.
4. Test owner / manager / driver, multiple companies/branches, 05:00 Cairo, repeated clicks, unfinished orders, archived report, realtime, GPS, QR, feedback, and restore.
5. Send full diff and evidence; ask for explicit approval before live publish.
6. No additional paid development authorized.
