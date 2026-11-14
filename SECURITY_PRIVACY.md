# Your Staff Delivery — security and device privacy baseline

Status: security work in progress. This is NOT a guarantee of 100% security or certification.

## Data boundaries
- Every authenticated request must be checked by Supabase server-side RLS or a role-checked RPC.
- Tenant isolation is company -> branch -> permitted staff account. UI hiding is never an authorization control.
- Suspended and pending-onboarding companies must not operate, including through privileged RPC bypasses.
- Platform owner credentials and signing keys must never be included in client source, GitHub, logs or APK.
- Do not embed customer or employee data in screenshots, analytics or build artifacts.

## Device privacy
- Do not request Android permissions for contacts, SMS, call logs, photos, microphone, camera, accessibility, device accounts or all-files access.
- Driver geolocation must be opt-in, role-limited, transparent, stoppable and sent only when required for active duty. Do not enable background location without separate implementation, disclosure and Play review.
- Do not use clipboard-reading, installed-app enumeration, advertising identifiers or invasive device fingerprinting.
- Protect session tokens; logout should clear sessions. Shared devices require a separate threat model.
- HTTPS only; no cleartext traffic; minimize third-party scripts and pin/bundle dependencies.
- Never display full phone numbers or addresses in public tracking endpoints.

## Mandatory pre-release verification
1. Real-account tests for owner, manager, call center, kitchen, supervisor, driver and complaints.
2. Negative tests: unauthorized branch/company, disabled account, suspended company, invalid stage transition, driver assigned to other branch.
3. Full order lifecycle and failed/offline/reconnect paths.
4. Review all SECURITY DEFINER RPCs and table policies; test under authenticated identities rather than service-role.
5. Verify privacy policy, account/data deletion process, retention, and Google Play Data Safety declarations.
6. Review generated AndroidManifest.xml and transitive plugin permissions. Verify no unexpected device permissions.
7. Scan dependencies, secrets and build artifacts. Perform independent penetration testing before paid customer launch.

## Reporting
Do not put live customer records, credentials, session tokens or security vulnerabilities in public GitHub issues. Use a private reporting channel.
