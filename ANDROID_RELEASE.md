# Your Staff Delivery — Android release preparation

## Status
Android scaffold only. No APK/AAB has been compiled or signed. Do not publish before full role, tenant-isolation, privacy and device tests.

## Build prerequisites
- Node.js and npm compatible with Capacitor 8
- Android Studio, Android SDK and JDK required by current Capacitor Android
- Secure Play App Signing configuration; never commit signing keys

## Steps
1. `npm install`
2. `npm run android:init` (once, generates native Android project)
3. `npm run android:sync` after every web change
4. `npm run android:open`
5. Test on a physical Android device and emulator
6. Generate signed Android App Bundle (AAB) using Android Studio for Play Console

## Architecture
- Copies existing website assets into local `www/` for Android. Does not use an unrestricted remote WebView.
- Supabase RLS and RPC permissions remain authoritative; do not put service-role keys in Android.
- Requires network access for Supabase and current external CDN dependencies.
- External CDN assets should be pinned and bundled locally before production.
- Geolocation, background tracking and push notification permissions are NOT configured. Implement and justify them before enabling.
- `com.yourstaff.delivery` is a proposed app ID; confirm ownership and uniqueness before Play submission.

## Release blockers
- Validate sign-in/out, expired sessions, password recovery, and every staff role
- Test cross-company/branch access with separate real test accounts
- Test orders, kitchen, supervisor dispatch, driver shift and location lifecycle
- Verify all enabled paid add-ons actually work, or keep them disabled
- Privacy policy, data safety declaration, account deletion process, support contact
- Android permissions and background location compliance
- Offline/reconnect handling, performance, Play policy and accessibility tests
- Release signing and Play Console account verification

No client or employee data should be embedded in test screenshots or repository files.
