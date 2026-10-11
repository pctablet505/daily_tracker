# Daily Tracker

A habit tracker for Android. It works offline, keeps its data on your phone, and stays out of your way: open it, tick what you did, close it.

## What it does

- **Today.** Every habit planned for the day, grouped as *To do*, *Staying clear* and *Done*, with a week strip to look back or fill in a missed day. Ticking, typing a number, adding a note or taking a photo takes one tap and one sheet.
- **Four kinds of entry.** Tick, number (with a goal and a unit), note, photo.
- **Habits you stay clear of.** Each day starts on track and you only log a slip. A habit can switch to *confirm* mode if you would rather tick it each day. A day with nothing logged and the app never opened does not count as clean.
- **Streaks you can trust.** A day keeps the streak when at least a set share of its planned habits are done (60% by default; change it in Settings). Days with nothing planned are skipped. Today never breaks a streak while it is still open.
- **Progress.** A month calendar, current and best streak, the last 30 days, perfect days, and a breakdown by area. Each habit has its own page with streaks, a 12-week map, a number chart and recent entries.
- **Reminders.** A time per habit, quiet hours, an evening check-in for habits you stay clear of, and *Done* / *In 1 hour* buttons on the notification.
- **Starter packs.** Ready-made sets (Healthy habits, Morning routine, Workout, Evening wind-down and more), and packs you can import from a `.json` file. A pack file is plain JSON, so a personal set of habits can live outside the app and be loaded on any phone.
- **Backup.** Save a JSON file anywhere, restore from one (a safety copy is kept first), or back up to your own Google Drive app folder (needs set-up, below). **Photos never leave the phone** and are not part of any backup.
- **App lock.** A 4 to 6 digit PIN, optional fingerprint, lock after a time away, your phone's lock as a way back in.
- **Updates.** The app checks this repository's GitHub releases, verifies the download against the published checksum, and hands it to Android to install.
- Light and dark theme, large-text friendly, screen-reader labels, CSV export of every entry.

## Build and run

You need Flutter 3.47.7, JDK 17 and the Android SDK (platform 37).

```bash
flutter pub get
flutter run                       # debug build, installs beside a release build as "Daily Tracker (debug)"
flutter analyze
flutter test                      # unit and widget tests, including every screen at double text size
```

On-device tests (a real phone or emulator, no mocks) live in `integration_test/`:

```bash
adb shell pm grant com.dailytracker.daily_tracker.debug android.permission.POST_NOTIFICATIONS
flutter test integration_test/reminders_test.dart -d <device id>
flutter test integration_test/notification_action_test.dart -d <device id>
```

`flutter test` removes the app when it finishes, so install the debug app and grant the permission first, as above.

## Releases

Pushing a tag such as `v2.0.0` builds, tests and publishes a signed APK with a `.sha256` file; the tag must equal `version:` in `pubspec.yaml`. Updates only install over the existing app if every release is signed with the **same key**, so the workflow refuses to run without one.

1. Make a key once and keep it safe (losing it means users must uninstall to update):

   ```bash
   keytool -genkeypair -v -keystore release.keystore -alias daily-tracker \
     -keyalg RSA -keysize 4096 -validity 10000
   ```

2. Add four repository secrets (Settings, Secrets and variables, Actions):
   `KEYSTORE_BASE64` (the output of `base64 -w0 release.keystore`), `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

3. For a local release build, put the same values in `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; git ignores it). Without a key, `flutter build apk --release` falls back to the debug key, which is fine for trying it out and useless for updating.

## Google Drive backup

Off until you give the build an OAuth client; the Backup screen says so while it is off. The backup file works without it.

1. In [Google Cloud Console](https://console.cloud.google.com/) create a project and enable the **Google Drive API**.
2. Set up the OAuth consent screen. The only scope used is `drive.appdata`: the app can see its own hidden folder and nothing else in your Drive.
3. Create an **Android** OAuth client with package `com.dailytracker.daily_tracker` and the SHA-1 of your release key (`keytool -list -v -keystore release.keystore`).
4. Create a **Web application** OAuth client and copy its client id.
5. Build with it: `flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`. In CI, add it as the `GOOGLE_SERVER_CLIENT_ID` secret.

## How it is built

Flutter, Riverpod, go_router, SQLite (sqflite). A day is a record, not a job: there is nothing that has to run at midnight, and the *Today* date moves on by itself.

```
lib/core       calendar days
lib/data       models, statistics and streak rules, database, backup format, packs
lib/logic      what each screen shows, as plain functions
lib/services   reminders, backup, Drive, updater, lock, photos
lib/state      providers and user actions
lib/ui         theme, shared widgets, sheets, screens
```

Statistics and reminder planning are plain Dart with no Flutter or database in them, and carry most of the tests.

## Left out on purpose

- Task priority, one-off tasks with due dates and date-specific reminders: this is a habit tracker.
- Swipe gestures, hero animations and loading shimmer.
- A daily reset job and WorkManager background tasks (a day is a record; reminders are scheduled with the system alarm manager).
- iOS, web and desktop builds.

## License

MIT License
