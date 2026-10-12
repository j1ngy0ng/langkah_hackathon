# Langkah — Android walking rewards

The regular Langkah app uses live Supabase authentication and database transactions. Its APK contains no demo login, simulated steps, local fake rewards or role switcher. Existing sample catalog records are archived and not shown as available rewards. The separate Sandbox APK described below is an isolated tool for remote testing.

## Install and run

To test full walking/reward interactions away from a mall, install the separate **Langkah Sandbox** APK at `output/Langkah-Sandbox-android.apk`. It uses the same app screens with local sample data, a persistent test banner, simulated location/steps and role switching. It requires no login and makes no Supabase calls. See [REMOTE_TESTING.md](REMOTE_TESTING.md) for the complete resident → reward → merchant → admin test journey and build commands. The regular Langkah APK retains genuine-location and hardware-step requirements.

The interface was redesigned for version **1.2.0+3**: forest green and ivory styling, a compact sign-in form with password visibility, a destination selector, expandable route details, a walking progress ring, saved voucher details in ticket cards, and clearer profile/staff activity summaries. Mission and wallet empty states link back to the mall mission list. `output/Langkah-ui-preview.png` shows Flutter-rendered layouts with test-only data; it does not establish actual sensor operation or live voucher availability.

Version **1.2.1+4** gives administrators a dedicated workspace: **Dashboard, Malls, Merchants, Rewards, Reports**. Admin accounts open on Dashboard after the server confirms their role. Personal Explore, Mission, Wallet and You pages are not constructed for administrators. The header account button contains account details, refresh, password recovery and sign-out. Malls retains operational route availability and staff QR controls. `output/Langkah-admin-preview.png` shows rendered admin layouts with test-only records.

Version **1.2.2+5** gives approved merchants two focused destinations: **Offers** and **Redeem**. They open on Offers, submit their assigned outlet's offers for approval and manage approved stock/open status. Redeem contains camera scanning and voucher-code validation. The header account screen shows their assigned shop and mall, account details, refresh, password recovery and sign-out. Personal walking/wallet screens and administrator tools are not constructed for merchants. Resident navigation and merchant applications remain unchanged; after approval and refresh, the server-backed role opens the merchant workspace. `output/Langkah-merchant-preview.png` shows actual Flutter renders with test-only offers, not a live campaign.

Install `output/Langkah-android.apk` on an Android phone with a hardware step counter. Allow installing this file when Android asks. Android 7 or later is required. The APK uses the current development signing key; use a dedicated release key before public distribution.

Version **1.2.3+6** fixes location diagnostics: a fresh mock location is rejected immediately with instructions to stop the location-changing app and clear **Developer options → Select mock location app**. Old mock readings do not prevent recovery once a fresh real reading arrives. Device errors display their readable message instead of raw `PlatformException` text. The fresh-reading (15 seconds), accuracy (75 metres), real-location and server mall-boundary requirements remain in force.

If mission check-in cannot get a location, enable Location, allow **Precise location** for Langkah, enable Google Location Accuracy where available and retry near the mall entrance. A GPS reading outside the configured mall boundary will still be refused. Android Studio's emulator can exercise location handling using Extended controls → Location, but does not establish actual presence at a mall or hardware walking performance; use a supported phone on site for that test.

Open this folder in Android Studio with the Flutter plugin, or run:

```powershell
cd C:\Users\user\Desktop\langkah_hackathon
.\run-android.ps1
# Or explicitly select the attached phone:
.\run-android.ps1 -Device YOUR_DEVICE_ID
```

`config/supabase.local.json` contains the supplied public client configuration and is excluded from Git. The app never needs a service-role key. Keep privileged keys and email credentials out of Flutter.

Build the connected APK:

```powershell
flutter build apk --release --dart-define-from-file=config/supabase.local.json
```

## Locations and real outlets

These are selected directory listings, not the malls' complete tenant lists. Names and lots were checked on 11 October 2026. Listing a real shop does not establish a voucher agreement.

| Mall | Outlet | Lot |
| --- | --- | --- |
| Elmina Lakeside Mall | ZUS Coffee | GF-95 & 96 |
| Elmina Lakeside Mall | Inside Scoop | GF-13A |
| Elmina Lakeside Mall | Decathlon | GF-97 |
| KL East Mall | ZUS Coffee | G2K-03A |
| KL East Mall | Inside Scoop | G1K-01 |
| KL East Mall | Decathlon | G2-17, G2-17A, G2-18, G2-19 & G2-20 |
| KLGCC Mall | Huckleberry | GF-13 |
| KLGCC Mall | Oh Cha Matcha | GFK-03 |
| KLGCC Mall | Jaya Grocer | GF-07 |

Official sources: [Elmina](https://www.simedarbyproperty.com/malls/elmina-lake-side-mall/), [KL East](https://www.simedarbyproperty.com/malls/kleast-mall/), [KLGCC](https://www.simedarbyproperty.com/malls/klgcc-mall/). The app links to these directories and stores the source and verification date alongside each shop. Mall centres come from the map links embedded in those official pages. Their initial radii need on-site review.

## Activate real use

Complete **Authentication email delivery** below before inviting residents or registering the administrator.

1. Register `ngjingyong168@gmail.com` in the app, confirm the email, then sign in. The first verified account with that exact email becomes administrator, provided no administrator already exists. Editable signup metadata cannot grant a staff role.
2. In **Malls → Mall location setup**, test each centre and radius on site. Set a radius covering the public walking areas and mark the review complete. The supplied map pins are starting points, not surveyed building boundaries.
3. Open the 500-step or 1,000-step missions in **Malls → Route availability** after reviewing safe public walking areas. No staff QR is required initially.
4. Shop representatives use **You → Request merchant access**. The administrator verifies their identity and outlet before approving in **Merchants → Merchant access requests**. Approved merchants can submit offers, manage stock and redeem only their outlet's vouchers.
5. Create an offer using the actual agreed title, terms, quantity, validity and campaign end date. In **Rewards**, the administrator records a merchant approval reference and publishes it. Merchants submit and manage their offers in **Offers**, then scan or validate visitors' voucher codes in **Redeem**. No invented discount is published by the seed migration.
6. Visitors choose a mall, start a mission there, resume tracking and walk with Langkah open. The screen remains awake while tracking. They choose one of up to three eligible rewards from that mall, then present the voucher to authorised staff for one-time redemption.

Voucher validity ends at the earlier of its issue-based validity and the campaign end. Issued vouchers store their original title, terms and outlet, so later catalog changes do not change the promise. Stock decrement and issuance are one transaction; retries return the same voucher. The current daily budget is two rewards per person, using Malaysia's date, and one reward per mission.

## How location verification works

- Android requests precise location and activity permission when a user starts walking. It uses the native cumulative step sensor, excluding pre-session totals and paused movement.
- At mission start and every 15 seconds during tracking, the app obtains a reading at most 15 seconds old with accuracy no worse than 75 metres. Android rejects locations marked as mock by its location service.
- Supabase checks coordinates, accuracy and freshness, then calculates distance from the mall's reviewed centre. A reading passes only when `distance + accuracy <= radius`.
- Server credit is monotonic and rate-bounded. A gap over 45 seconds cannot award new steps; resuming starts a fresh verification interval. A failed check stops tracking and drops the unverified interval rather than silently counting it.
- Tracking pauses when Langkah enters the background. Verified progress stays in Supabase and resumes after reopening. This version does not award background or screen-locked walking credit.
- Only the latest mission coordinates are stored, not a trail of every position. Reports record the selected mission, category and user-written description.

GPS verifies a configured vicinity; it cannot distinguish indoor floors or perfectly exclude every adjacent outdoor space. Location age, coordinates and sensor data still originate from a client and a modified device could falsify them. These checks are not proof against every form of cheating. On-site trials are needed before promising reliable indoor detection.

## Optional staff QR verification

When staff can host checkpoints, enable **Require rotating staff QR** in **Malls → Mall location setup**. Use an administrator device's **Display rotating check-in QR** screen under **Malls → Route availability** for each open mission, choosing Start or Finish. New missions require fresh GPS plus a current start token; finishing requires the step goal, fresh GPS and a current finish token. Existing sessions keep their original QR requirement.

The server creates random 60-second tokens scoped to the mission and checkpoint. Static codes and expired tokens are rejected. Visitors scan with their phone camera or type the displayed code. QR images can still be forwarded during their validity window; this reduces replay risk but does not guarantee physical presence.

## Authentication email delivery

**Current zero-cost delivery configuration:** Gmail custom SMTP is saved and enabled with the settings below. The user entered the app password privately; Supabase indicates a stored hidden password. The Send Email delivery hook is saved as **DISABLED**, so authentication emails use SMTP rather than Resend. Email signups and email confirmation remain enabled. The user retried signup with their student email and reported that it works now. The confirmation template uses `{{ .ConfirmationURL }}`, and the Site URL and allowed redirect remain `langkah://auth/callback`. Password recovery and completion of the Android confirmation callback have not been separately verified. No APK update is required for this delivery change. The existing Resend deployment remains available for a future verified-domain setup.

| SMTP field | Value |
| --- | --- |
| Sender email | `ngjingyong168@gmail.com` |
| Sender name | `Langkah` |
| Host | `smtp.gmail.com` |
| Port | `465` |
| Username | `ngjingyong168@gmail.com` |
| Password | Google app password, entered privately by the user |
| Minimum interval per user | `60` seconds |

Google app passwords require 2-Step Verification and may be unavailable for some account configurations. Use the personal Gmail account rather than the student account. Create an app password named Langkah, enter it in Supabase's SMTP Password field without the display spaces, and save. Do not use the ordinary Gmail sign-in password or paste credentials into chat. Supabase initially limits custom SMTP to 30 messages per hour; Gmail has its own sending limits, and personal SMTP deliverability must be tested. This path is for a small rollout, not an unlimited email service. [Google app passwords](https://support.google.com/accounts/answer/185833), [Gmail SMTP](https://developers.google.com/workspace/gmail/imap/imap-smtp), [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

The remainder of this section records the earlier Resend configuration and its pending domain verification. SMTP now uses the configured Supabase email templates. If the Send Email hook is re-enabled, it takes precedence over SMTP. [Supabase delivery behaviour](https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook#email-sending-behavior).

The Android callback `langkah://auth/callback` is installed in AndroidManifest.xml and configured as both Supabase Site URL and an exact allowed redirect. Account confirmation and password recovery links should be opened on the same Android phone that initiated the request. Recovery opens the password update screen. Email confirmation remains enabled.

Mystery Malaysia's repository uses Resend through a signed Supabase Send Email Hook: `supabase/functions/send-email/index.ts` at commit `25aa11a56a450124ae036c2aea89b60977f4a634`. Langkah adapts that architecture in `supabase/functions/langkah-send-email/index.ts`, with its own branding and Android callback. Mystery Malaysia's Supabase project was inactive when checked; its existing sender domain and delivery cannot be assumed working.

The Langkah function is deployed at:

```text
https://amhwkquizcgvjrlfszay.supabase.co/functions/v1/langkah-send-email
```

It verifies the raw-body webhook signature before sending, supports confirmation/recovery/invitation/magic-link/email-change/reauthentication, and returns success only after Resend accepts delivery. Email-change requests send each hash to its correct recipient. Provider requests use event-and-recipient idempotency keys for retries. Credentials and verification links are not logged. This function uses webhook signatures rather than end-user JWTs; `supabase/config.toml` declares that setting.

**Resend state (11 October 2026):** all three required secret names remain present in the Langkah project. The Send Email hook retains the URL above but is now saved as disabled. The deployed function previously rejected an unsigned POST with 401. Secret values were not copied into the app or repository. This function no longer handles authentication delivery while the hook is disabled.

**Signup troubleshooting:** the initial signing-secret mismatch was corrected by the user. Subsequent requests reached Resend and received HTTP 400, which the hook reports as 502. The sender had been set to a personal Gmail address. It is now temporarily `Langkah <onboarding@resend.dev>` for testing with the email associated with the Resend account only. Public resident/merchant signup requires replacing this with a sender on a domain verified in Resend. The function now logs redacted provider validation details; real email delivery remains unverified. Keep the existing hook secret; do not generate another unless deliberately rotating both settings together.

**Earlier blocker:** a retry with the improved diagnostics returned `400 API key is invalid`; the provider key and hook secret had identical digests. The latest Resend log now recognises the Langkah API key and rejects delivery with **403 testing domain restriction** instead, so that earlier key error is no longer the current diagnosis.

**Resend-only blocker:** the student-email signup reached Resend but was rejected because `AUTH_EMAIL_FROM` uses `Langkah <onboarding@resend.dev>`. This sender only sends to the Resend account email. The only listed custom domain, `mail.mysterymalaysia.com`, was Not Started; a DNS verification attempt shows Pending. Its root NS and required TXT/CNAME records returned DNS name does not exist from the local resolver. To use Resend for other residents in future, add the exact DNS records shown in Resend for a domain you control, wait for Verified, then set `AUTH_EMAIL_FROM` to `Langkah <auth@YOUR_VERIFIED_DOMAIN>` directly in Supabase. Keep the working API key and hook secret unchanged. These Resend secrets do not configure the current Gmail SMTP sender.

The setup steps below describe the earlier Resend path. Use them only for a new project or a deliberate switch from SMTP after verifying a sender domain:

1. In Supabase **Authentication → Auth Hooks → Add hook → Send Email hook**, select HTTPS and enter the URL above. Generate a **new Langkah** secret, keep the hook disabled and create it.
2. In **Edge Functions → Secrets**, enter `RESEND_API_KEY`, `AUTH_EMAIL_FROM` (for example `Langkah <auth@your-verified-domain>`), and `SEND_EMAIL_HOOK_SECRET` (the full `v1,whsec_...` secret from step 1). Use your existing Resend account and sender domain if they are verified and the key permits that domain. Keep these values on the server.
3. Return to **Authentication → Auth Hooks**, edit the Send Email hook and enable it. Keep account email confirmation enabled. This hook replaces SMTP/template delivery; custom SMTP is unnecessary for this approach. [Supabase Send Email Hook](https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook).
4. On an Android phone, register an email outside the Supabase project team and confirm it. Test password recovery on the same phone. Verify actual inbox arrival and callback handling before opening signup to residents.

The default `onboarding@resend.dev` sender only supports testing to the Resend account owner's address. Sending to other residents through Resend requires a verified sender domain. [Resend sender restrictions](https://resend.com/docs/knowledge-base/403-error-resend-dev-domain).

For future function updates:

```powershell
npx.cmd --yes deno test supabase/functions/langkah-send-email/index_test.ts
npx.cmd --yes supabase@latest functions deploy langkah-send-email --project-ref amhwkquizcgvjrlfszay --use-api
```

If configuring secrets through the CLI, copy `supabase/email.env.example` to `supabase/email.local.env`, fill it privately, then run `npx.cmd --yes supabase@latest secrets set --project-ref amhwkquizcgvjrlfszay --env-file supabase/email.local.env`. That local file is excluded from Git. Do not deploy or change Mystery Malaysia's project while setting up Langkah.

## Database and checks

Migrations `001_langkah.sql` through `005_claim_alias.sql` have been applied to the supplied project. Do not rerun the table-creation migrations on that project. For a new empty project, run the migrations in numeric order. `004_admin_bootstrap.sql` contains the explicitly designated initial administrator email; change it before using an unrelated project.

Run `supabase/verify.sql` in SQL Editor to exercise fresh/outside GPS rejection, progress bounds, old-client bypass prevention, offer approval, mall scope, stock and retry atomicity, daily limits, authorised one-time redemption, expired/ordered staff QR and authenticated RLS. All fixtures and catalog changes roll back. A passing run ends with PASS.

```powershell
flutter analyze
flutter test
```

See `VERIFICATION.md` for what was checked and what still requires a physical phone, email service and real merchant/site participation. This app has connected workflows; it has not yet been field-tested or certified ready for public launch.
