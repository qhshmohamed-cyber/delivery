# Safe staged integration — Your Staff Delivery
Do NOT overwrite the live TackHost public_html/index.html with the GitHub index: the GitHub default branch is behind the production site.

## Database
Supabase has already been updated (2026-11-17) with:
- one active customer-navigation target per driver
- explicit driver-only route selection / stop / current-route RPCs
- server-side filtering of GPS and pilot phone in public tracking
- automatic selection on the driver's existing "خرج للتوصيل" action
- automatic clearing on delivery/failure/reassignment
- separate per-manager "تمت القراءة" receipts, without changing complaint statuses.

## Frontend staging
1. Back up TackHost public_html/index.html and existing JS assets.
2. In Test only, copy navigation-target.js and manager-complaint-read.js beside index.html.
3. Add these references to Test/index.html, retaining all existing production scripts:
   <script defer src="navigation-target.js?v=20261117"></script>
   <script defer src="manager-complaint-read.js?v=20261117"></script>
4. Test driver account with two assigned orders and two independent tracking links on two devices.
5. Confirm only the actively selected order returns GPS (and phone); the other sees no coordinates.
6. Press "تمت القراءة" as manager A. It must disappear for A, remain for manager B, and still exist in complaint reports.
7. Test that updating the complaint makes it reappear for A.
8. Verify tenant/branch access and all existing staff features; only then port these two script links into the *current* production index.html.
9. On rollback, remove ONLY these two script tags/assets. Server-side route privacy remains fail-closed.

IMPORTANT: Browser/PWA background GPS cannot be guaranteed while screen is locked; real-device tests are required.
