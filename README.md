# Event Scanner App

Offline-first Flutter app for QR-based attendance and resource collection
(basket / radio) tracking at events. Works fully offline; syncs scan logs to
a Google Sheet whenever the device regains connectivity.

## What's included

```
qr_scanner_app/
├── lib/                      # Flutter app source
│   ├── models/                # User, Staff, ScanRecord/Purpose
│   ├── db/                    # SQLite helper (seeds + storage)
│   ├── services/               # Session (device id/operator), Sync
│   └── screens/                # Login, Home (purpose picker), Scan
├── assets/
│   ├── users_sample.json      # 10 dummy people - REPLACE with real roster
│   └── staff_sample.json      # 3 dummy staff PINs - REPLACE with real staff
├── apps_script/
│   └── Code.gs                 # Paste into Google Apps Script (see below)
├── tools/
│   └── generate_qr_codes.py    # Generates printable QR badges from a CSV
└── pubspec.yaml
```

## 1. Getting the app running locally

This was scaffolded without a live Flutter SDK, so you'll need to do a
one-time setup on your own machine:

```bash
cd qr_scanner_app
flutter create .          # generates the native android/ and ios/ folders
flutter pub get
flutter run                # runs on a connected device/emulator
```

`flutter create .` will not overwrite the `lib/`, `assets/`, or
`pubspec.yaml` files already here - it only fills in the native
`android/` and `ios/` project scaffolding you need for permissions,
signing, and store deployment.

### Camera permissions (required for QR scanning)

After running `flutter create .`, add:

**`android/app/src/main/AndroidManifest.xml`** — inside the `<manifest>` tag:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```

**`ios/Runner/Info.plist`** — inside the top-level `<dict>`:
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to scan attendee QR codes.</string>
```

## 2. Swapping in your real data

Replace the two files in `assets/`:
- `users_sample.json` — your ~1000 people, format: `[{"id": "...", "name": "...", "role": "...", "group": "..."}, ...]`
- `staff_sample.json` — your real staff PINs, format: `[{"name": "...", "pin": "..."}, ...]`

The app seeds its local database from these files **only on first launch**
(when the local tables are empty). If you need to reload data on a device
that's already been used, uninstall and reinstall the app, or ask me to add
a manual "re-import" screen — not built yet since it wasn't part of the v1 scope.

Send me your real CSV (`id, name, role, group`) whenever it's ready and I'll
generate the properly formatted `users_sample.json` for you.

## 3. Generating printable QR badges

Each person's QR code encodes only their `id` — the app looks up
name/role/group locally. Generate printable PNGs with:

```bash
cd tools
pip install qrcode[pil]
python generate_qr_codes.py your_users.csv output_folder/
```

This produces one PNG per person (e.g. `U001_Ada_Okafor.png`), ready to lay
out on badge templates in Canva/Word/etc.

## 4. Setting up Google Sheets sync

1. Create a new Google Sheet.
2. Rename the first tab to exactly `ScanLogs`.
3. Add this header row: `id | name | role | group | purpose | timestamp | deviceId | operator`
4. In the Sheet: **Extensions → Apps Script**.
5. Delete any starter code, paste in the contents of `apps_script/Code.gs`.
6. Click **Deploy → New deployment**.
   - Type: **Web app**
   - Execute as: **Me**
   - Who has access: **Anyone**
   - Click **Deploy**, authorize when prompted.
7. Copy the resulting Web App URL.
8. Paste it into `lib/services/sync_service.dart`, replacing:
   ```dart
   const String kAppsScriptUrl = 'PASTE_YOUR_APPS_SCRIPT_WEB_APP_URL_HERE';
   ```
9. Rebuild the app. Test by scanning something with the device online — a
   row should appear in `ScanLogs` within a few seconds.

If you ever update the script code, you'll need to create a **new
deployment version** (Deploy → Manage deployments → Edit → New version) for
changes to take effect on the same URL.

## 5. How offline sync works

- Every scan is saved to the local SQLite database immediately, regardless
  of connectivity — the app never blocks on network.
- On app resume (foreground) and right after each scan, the app checks
  connectivity and pushes any unsynced records to the Sheet.
- There's also a manual **"Sync now"** button on the home screen.
- Duplicate/repeat scans are allowed and all logged — no blocking, no
  conflict resolution needed across multiple devices.

## 6. Distribution (both platforms, personal devices, <10 people)

**Android**: Build a release APK (`flutter build apk --release`) and share
it directly (Drive link, WhatsApp, etc.), or use Firebase App Distribution
for a nicer install flow. No developer account needed.

**iOS**: Requires an Apple Developer Program account ($99/yr) — unavoidable
for installing on personal iPhones outside the App Store. Once you have
that:
1. In App Store Connect, create the app record.
2. Build and upload via Xcode or `flutter build ipa`.
3. Add your ~10 staff as **Internal Testers** in TestFlight (just their
   Apple ID emails) — internal testing skips App Review entirely, so
   installs are near-instant.
4. Each person installs the **TestFlight** app, accepts the invite, installs
   your app.

## Notes / things intentionally left out of v1

- No in-app roster re-import UI (uninstall/reinstall to reseed for now).
- No admin dashboard/reporting inside the app — reporting happens in the
  Google Sheet itself.
- No background sync while the app is fully closed — sync triggers on
  app open/resume and after each scan, which is reliable and avoids
  iOS's background-execution restrictions.
