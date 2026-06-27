# Daily Tracker

A cross-platform daily task tracker app built with Flutter. Features a modern Material 3 UI, offline-first local storage, Google Drive sync, automatic GitHub-based updates, reminders, analytics, and more.

## Features

- **Daily Checklist**: Create and manage your daily tasks with an intuitive checklist interface
- **Smart Reminders**: Set time-based reminders for tasks with local notifications
- **Recurring Tasks**: Automatically reset tasks daily
- **Analytics Dashboard**: Track completion rates, streaks, and weekly progress
- **Calendar View**: View and manage tasks by date
- **Task Templates**: Quickly add pre-defined task sets (Morning Routine, Workout, etc.)
- **Google Drive Sync**: Backup and sync your data across devices
- **Auto Updates**: Check for and install new APK versions from GitHub releases
- **Export/Import**: Backup your data as JSON or export analytics as CSV
- **App Lock**: PIN and biometric authentication support
- **Dark/Light Theme**: Full Material 3 theming support
- **Polished UI/UX**: Shimmer loading skeletons, confetti burst on completion, Hero title transitions, and a daily completion progress ring
- **Offline First**: Works without internet; syncs when connected

## Tech Stack

- **Framework**: Flutter 3.27.1
- **State Management**: Riverpod
- **Database**: SQLite (sqflite)
- **Navigation**: go_router
- **Charts**: fl_chart
- **Notifications**: flutter_local_notifications
- **Background Tasks**: WorkManager
- **Google Drive**: googleapis + google_sign_in

## Project Structure

```
lib/
├── core/
│   ├── constants/
│   ├── database/
│   ├── extensions/
│   ├── theme/
│   └── utils/
├── data/
│   ├── local/
│   ├── models/
│   └── repositories/
├── domain/
│   └── entities/
├── presentation/
│   ├── features/
│   │   ├── analytics/
│   │   ├── calendar/
│   │   ├── onboarding/
│   │   ├── settings/
│   │   ├── tasks/
│   │   ├── templates/
│   │   └── update/
│   ├── providers/
│   └── router/
└── services/
    ├── background/
    ├── notification/
    └── sync/
```

## Building

### Prerequisites
- Flutter SDK 3.27.1+
- Android SDK 35
- Java 17

### Debug Build
```bash
flutter build apk --debug
```

### Release Build
```bash
flutter build apk --release
```

### Tests
```bash
# Unit + widget tests (161 tests)
flutter test

# Integration test on a connected Android device (e.g., Pixel 9)
flutter test integration_test/app_test.dart -d 49201FDAQ0009X
```

## Auto Update Mechanism

The app checks the GitHub releases API for new versions. When a new APK is published:

1. App detects available update on launch or via background check
2. Shows changelog and download progress
3. Downloads APK to temporary storage
4. Triggers Android system installer

**Release Naming**: Tag releases as `v1.0.0`, `v1.1.0`, etc. The CI workflow automatically attaches `app-release.apk` to the release.

## Google Drive Sync Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable the Google Drive API
4. Configure OAuth consent screen
5. Create Android OAuth 2.0 credentials with your package name and SHA-1
6. Download `google-services.json` and place in `android/app/`

## License

MIT License
