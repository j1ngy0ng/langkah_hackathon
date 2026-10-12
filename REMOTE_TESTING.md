# Test Langkah from anywhere

Install `output/Langkah-Sandbox-android.apk`. It appears as **Langkah Sandbox** and installs alongside **Langkah**. No login, Supabase setup, fake-GPS app or Android Developer options are needed. The orange SANDBOX strip stays visible on every screen.

The sandbox uses the regular resident, merchant and administrator screens with in-memory sample records. The three mall names and selected shop names come from the existing catalog. All offers and voucher codes are marked TEST ONLY. They have no monetary value and shops will not accept them. The sandbox does not connect to Supabase or alter real mall settings, stock, accounts or vouchers. Official directory links can still open a browser.

## Complete a walking and reward journey

1. Open **Langkah Sandbox**. It starts as Resident with Elmina Lakeside Mall selected. You can also select KL East Mall or KLGCC Mall.
2. Scroll to a 500-step mission and tap **Start this mission**.
3. On Mission, scroll down and tap **Resume step tracking**.
4. Tap the orange strip's **Test controls**, then **+500 steps**. Close controls. The mission should show 500 steps and a completed goal. The +100 button lets you check gradual progress instead.
5. Tap **Choose my reward**, choose one of the three available sample offers and tap **Choose this reward**. The sample stock decreases by one and a voucher appears in Wallet.
6. On the voucher screen, tap **Copy voucher code**. Note the named shop and mall. Codes start with `TEST-`.
7. Open **Test controls**, select that shop in **Merchant outlet to test**, then tap **Merchant**. The app changes to Offers/Redeem, keeping the same sample data.
8. Tap **Redeem**, paste the code into **Visitor's voucher code**, then tap **Validate and redeem**. Reusing the same code should fail. Choosing a different outlet should also fail.
9. Switch back to Resident and open Wallet. The voucher should now show Redeemed.

Switching roles closes open pages and pauses simulated tracking. To continue an unfinished walk, switch back to Resident, tap Continue mission, then Resume step tracking.

## Test errors and edge cases

Use **Test controls → Simulated location** before starting a mission or adding steps:

| Setting | Expected result |
| --- | --- |
| Inside mall | Check-in and simulated walking accepted |
| Outside mall | Boundary rejection |
| Mock GPS | Readable mock-location message |
| Weak accuracy | Accuracy rejection |
| Stale GPS | Fresh-location requirement |
| No GPS fix | Readable location-timeout message |
| Location off | Instruction to enable location |

Return to Inside mall to continue. Location follows the selected mission's mall; it does not read your actual location.

- Adding steps before starting/resuming tracking shows instructions instead of awarding steps.
- A 1000-step mission needs two +500 increments.
- Claiming before the target is reached is blocked.
- Two claimed rewards exhaust the sample resident's daily allowance. The resident can still walk. Reset sample data to repeat a test from the start.
- **Expire latest sample voucher** changes the newest voucher to expired. Merchant redemption must reject it.
- As Admin, pause a route or set stock to zero and check Resident availability. Local boundary settings can be edited to reproduce the review gate. These edits affect only sandbox records, not reviewed real mall boundaries.

## Check merchant and administrator tools

- **Reports:** Resident → Mission → Report a route issue; submit a sample description. Switch to Admin → Reports and mark it resolved. The dashboard should reflect the local activity and issued/redeemed vouchers.
- **Merchant requests:** Resident → You → Request merchant access. Submit sample contact details. Switch to Admin → Merchants and approve or reject the request. The role selector remains a testing control, not proof of real authentication or access enforcement.
- **Offer approval:** Switch to Merchant → Offers → Create shop offer. Submit a sample title, terms, stock and campaign end. Switch to Admin → Rewards, enter a test reference and approve it. Switch to Resident and inspect the mall's available offers. The picker shows at most three available offers; temporarily pause the seeded offers to inspect a new one.
- **Outlet filtering:** Choose a different outlet in Test controls, then inspect Merchant → Offers. Only that outlet's offers should appear.
- **Optional QR:** Admin → Malls → Mall location setup can require staff QR for local sample data. Use the staff QR screen to obtain start/finish codes and enter them through the scanner's manual code field. Start codes are required before beginning; finish codes are required after reaching the step goal. Codes expire after 60 seconds. A second screen/device is useful for camera scanning.

**Reset sample data** clears local walks, vouchers, reports, requests and edits and restores the sample catalog. Data also resets when the app process restarts; it is intentionally not persisted.

## What still needs the regular app

Use the regular Langkah app to test real signup, confirmation email, login, password recovery, server-assigned roles and merchant applications from anywhere. Sandbox accounts do not send email or have passwords. Offline tests do not verify Supabase authentication, RLS, atomic stock updates or concurrent redemption; the existing server verification covers those rules separately.

Genuine GPS accuracy, mall-boundary coverage, hardware step sensing, background pause/resume and real shop acceptance need a supported phone and an eventual on-site test. The sandbox demonstrates the interaction; it does not establish physical presence or redeemable merchant offers.

## Build and run from Android Studio / terminal

Open the project in Android Studio with the Flutter plugin. Create a Flutter run configuration with Dart entrypoint `lib/sandbox.dart` and additional run args `--dart-define=LANGKAH_SANDBOX=true`. Choose an Android emulator or phone. No Supabase configuration is used for this entrypoint.

```powershell
cd C:\Users\user\Desktop\langkah_hackathon
.\build-sandbox.ps1
# Or run directly on your chosen Android device:
flutter run --target=lib/sandbox.dart --dart-define=LANGKAH_SANDBOX=true -d DEVICE_ID
# Run the local sandbox workflow and UI checks:
flutter test --dart-define=LANGKAH_SANDBOX=true test/sandbox_test.dart
```

The build flag selects Android package `com.example.langkah_hackathon.sandbox`, label Langkah Sandbox and callback scheme `langkah-sandbox`. Normal builds retain the original package, label and `langkah` callback. The normal entrypoint refuses the sandbox flag so it cannot combine simulated inputs with a live Supabase session accidentally. `build-sandbox.ps1` copies only the sandbox APK; it preserves `output/Langkah-android.apk`.
