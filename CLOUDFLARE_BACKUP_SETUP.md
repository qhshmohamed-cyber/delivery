# Your Staff Delivery — Cloudflare Pages standby

This branch is a frozen backup of the static application. Do not modify the production branch or production database during deployment.

## Cloudflare Pages setup

- Choose Workers & Pages → Create → Pages → Connect to Git.
- Repository: `qhshmohamed-cyber/delivery`.
- Production branch: `backup-2026-11-15`.
- Framework preset: None.
- Build command: leave blank (no build required).
- Build output directory: `/` (repository root).
- Use a unique project name, e.g. `yourstaff-delivery-standby`.
- Verify every referenced asset is deployed and the login page loads over HTTPS.
- Check whether authentication redirects, CORS, Content Security Policy, PWA scope, and third-party API allowlists need the new domain.
- Test role-restricted login and full callcenter → kitchen → supervisor → driver workflow in a safe test branch or test tenant before real failover.
- The standby uses the same Supabase backend, so it is NOT a database backup and cannot recover from a Supabase outage.
- Keep deployment manual while this branch is frozen. Review RLS and secrets before exposing additional endpoints.
- Never commit service-role credentials, API secrets, or employee/customer exports.
