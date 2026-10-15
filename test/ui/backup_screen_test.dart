import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/services/cloud_backup.dart';
import 'package:daily_tracker/services/drive_backup.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:daily_tracker/ui/format.dart';
import 'package:daily_tracker/ui/screens/backup_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import '../helpers/fake_drive.dart';
import 'harness.dart';

final class _Network implements NetworkInfo {
  bool wifi = true;
  @override
  Future<bool> isOnWifi() async => wifi;
  @override
  Future<bool> isOnline() async => true;
}

/// Database and file work needs real time: lets it finish, then settles.
Future<void> letItRun(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  setUpAll(loadAppFont);

  late FakeAuth auth;
  late FakeDrive drive;
  late _Network network;
  late CloudBackup cloud;
  late DateTime now;

  /// The Backup screen over a real Drive backup service, signed in (unless
  /// not [signedIn]), with automatic backup on and, when [backedUp], one
  /// backup made.
  Future<void> pumpSignedIn(
    WidgetTester tester, {
    bool signedIn = true,
    bool backedUp = true,
    Future<void> Function()? before,
  }) async {
    final overrides = await baseOverrides(ledger: sampleLedger());
    final prefs = await SharedPreferences.getInstance();
    await tester.runAsync(() async {
      final db = await openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
        singleInstance: false,
      );
      addTearDown(() => tester.runAsync(db.close));
      final repo = HabitRepository(db);
      await repo.addHabit(habit('a'));
      final safety = await Directory.systemTemp.createTemp('dt_backup_ui_');
      addTearDown(() => tester.runAsync(() => safety.delete(recursive: true)));
      auth = FakeAuth(signedIn: false);
      drive = FakeDrive();
      network = _Network();
      now = DateTime.utc(2026, 10, 11, 12);
      final backup = BackupService(
        repo: repo,
        readSettings: () => const Settings(),
        applySettings: (_) async {},
        safetyDir: () async => safety,
        now: () => now,
        appVersion: () async => '2.0.0',
      );
      cloud = CloudBackup(
        auth: auth,
        drive: DriveBackup(auth, MockClient(drive.handle)),
        backup: backup,
        network: network,
        prefs: prefs,
        now: () => now,
        wifiOnly: () => true,
      );
      if (signedIn) {
        await cloud.signIn();
        await cloud.setAutoBackup(true);
        if (backedUp) await cloud.backupNow();
      }
      await before?.call();
    });
    overrides.add(cloudBackupProvider.overrideWithValue(cloud));
    await pumpScreen(tester, const BackupScreen(), overrides: overrides);
  }

  group('a lost Google session', () {
    testWidgets('offers Sign in again, which keeps automatic backup on', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        before: () async {
          auth.signedIn = false;
          now = now.add(const Duration(days: 1));
          await cloud.autoBackupIfDue();
        },
      );
      expect(find.text('Sign in again'), findsOneWidget);

      await tester.tap(find.text('Sign in again'));
      await letItRun(tester);
      expect(auth.signedIn, isTrue);
      expect(cloud.sessionLost, isFalse);
      expect(cloud.autoBackup, isTrue);
      expect(find.text('Sign in again'), findsNothing);
    });

    testWidgets('shows why the automatic backup stopped', (tester) async {
      await pumpSignedIn(
        tester,
        before: () async {
          auth.signedIn = false;
          now = now.add(const Duration(days: 1));
          await cloud.autoBackupIfDue();
        },
      );
      expect(find.textContaining('Sign in to Google first.'), findsOneWidget);
    });
  });

  group('a backup this phone did not make', () {
    testWidgets('is named in place of "Not backed up yet."', (tester) async {
      await pumpSignedIn(
        tester,
        backedUp: false,
        before: () async => drive.files['old'] = (
          name: driveFileName,
          content: 'another phone',
          modified: DateTime.utc(2026, 10, 1, 12),
        ),
      );
      expect(
        find.textContaining(
          'A backup from ${shortDate(const DayKey(2026, 10, 1))} is on Drive',
        ),
        findsOneWidget,
      );
      expect(find.text('Not backed up yet.'), findsNothing);
    });

    testWidgets('is named after signing in on a new phone', (tester) async {
      await pumpSignedIn(
        tester,
        signedIn: false,
        before: () async => drive.files['old'] = (
          name: driveFileName,
          content: 'another phone',
          modified: DateTime.utc(2026, 10, 1, 12),
        ),
      );
      await tester.tap(find.text('Sign in with Google'));
      await letItRun(tester);
      expect(find.textContaining('is on Drive'), findsOneWidget);
    });

    testWidgets('is not looked for again once this phone backs up', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        backedUp: false,
        before: () async => drive.files['old'] = (
          name: driveFileName,
          content: 'another phone',
          modified: DateTime.utc(2026, 10, 1, 12),
        ),
      );
      await tester.tap(find.text('Back up now'));
      await letItRun(tester);
      expect(find.textContaining('is on Drive'), findsNothing);
      expect(find.textContaining('Last backup:'), findsOneWidget);
    });

    testWidgets(
      'cannot be looked for offline, and the screen says nothing of it',
      (tester) async {
        await pumpSignedIn(
          tester,
          backedUp: false,
          before: () async => drive.failWith = 503,
        );
        expect(find.text('Not backed up yet.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets(
    'restoring a backup another phone left makes it this phone\'s own',
    (tester) async {
      await pumpSignedIn(
        tester,
        before: () async {
          final id = drive.files.keys.single;
          final file = drive.files[id]!;
          drive.files[id] = (
            name: file.name,
            content: file.content,
            modified: drive.now.add(const Duration(hours: 3)),
          );
        },
      );
      expect(find.textContaining('is on Drive'), findsOneWidget);

      await tester.tap(find.text('Restore from Google Drive'));
      await letItRun(tester);
      await tester.tap(find.text('Replace everything'));
      await letItRun(tester);
      expect(find.textContaining('is on Drive'), findsNothing);
      expect(
        await tester.runAsync(cloud.otherBackupOnDrive),
        isNull,
        reason: 'automatic backup carries on over the restored file',
      );
    },
  );

  group('a restore from Drive on mobile data with Wi-Fi only on', () {
    testWidgets('can go ahead over mobile data', (tester) async {
      await pumpSignedIn(tester, before: () async => network.wifi = false);
      await tester.tap(find.text('Restore from Google Drive'));
      await letItRun(tester);
      expect(find.text('Not on Wi-Fi'), findsOneWidget);

      await tester.tap(find.text('Use mobile data'));
      await letItRun(tester);
      expect(find.text('Replace everything on this phone?'), findsOneWidget);
    });

    testWidgets('can wait for Wi-Fi', (tester) async {
      await pumpSignedIn(tester, before: () async => network.wifi = false);
      await tester.tap(find.text('Restore from Google Drive'));
      await letItRun(tester);
      await tester.tap(find.text('Wait for Wi-Fi'));
      await letItRun(tester);
      expect(find.text('Replace everything on this phone?'), findsNothing);
      expect(find.text('Not on Wi-Fi'), findsNothing);
    });
  });

  testWidgets(
    'a backup on mobile data with Wi-Fi only on can go ahead over mobile data',
    (tester) async {
      await pumpSignedIn(tester, before: () async => network.wifi = false);
      final uploads = drive.requests.where((r) => r.startsWith('PATCH')).length;
      await tester.tap(find.text('Back up now'));
      await letItRun(tester);
      await tester.tap(find.text('Use mobile data'));
      await letItRun(tester);
      expect(
        drive.requests.where((r) => r.startsWith('PATCH')).length,
        uploads + 1,
      );
    },
  );

  testWidgets('a working session offers no Sign in again', (tester) async {
    await pumpSignedIn(tester);
    expect(find.text('Sign in again'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
