import 'dart:io';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/services/cloud_backup.dart';
import 'package:daily_tracker/services/drive_backup.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import '../helpers/fake_drive.dart';

final class FakeNetwork implements NetworkInfo {
  bool wifi = true;
  bool online = true;
  @override
  Future<bool> isOnWifi() async => wifi;
  @override
  Future<bool> isOnline() async => online;
}

void main() {
  sqfliteFfiInit();
  late HabitRepository repo;
  late FakeDrive drive;
  late FakeAuth auth;
  late FakeNetwork net;
  late CloudBackup cloud;
  late SharedPreferences prefs;
  var now = DateTime.utc(2026, 10, 11, 12);
  var wifiOnly = true;
  var settings = const Settings();

  setUp(() async {
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    repo = HabitRepository(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    drive = FakeDrive();
    auth = FakeAuth(signedIn: false);
    net = FakeNetwork();
    now = DateTime.utc(2026, 10, 11, 12);
    wifiOnly = true;
    settings = const Settings(streakThreshold: 80);
    final safety = await Directory.systemTemp.createTemp('dt_cloud_');
    addTearDown(() => safety.delete(recursive: true));
    final backup = BackupService(
      repo: repo,
      readSettings: () => settings,
      applySettings: (m) async => settings = settings.withImported(m),
      safetyDir: () async => safety,
      now: () => now,
      appVersion: () async => '2.0.0',
    );
    cloud = CloudBackup(
      auth: auth,
      drive: DriveBackup(auth, MockClient(drive.handle)),
      backup: backup,
      network: net,
      prefs: prefs,
      now: () => now,
      wifiOnly: () => wifiOnly,
    );
    await repo.addHabit(habit('a'));
    await repo.setEntry(entry('a', mon));
  });

  test('is not signed in at first and says so', () {
    expect(cloud.email, isNull);
    expect(cloud.lastBackupAt, isNull);
  });

  test('signing in remembers the account', () async {
    await cloud.signIn();
    expect(cloud.email, 'me@example.com');
    final again = CloudBackup(
      auth: auth,
      drive: DriveBackup(auth, MockClient(drive.handle)),
      backup: cloud.backupForTest,
      network: net,
      prefs: prefs,
      now: () => now,
      wifiOnly: () => wifiOnly,
    );
    expect(again.email, 'me@example.com');
  });

  test(
    'signing out forgets the account but leaves the backup on Drive',
    () async {
      await cloud.signIn();
      await cloud.setAutoBackup(true);
      await cloud.backupNow();
      await cloud.signOut();
      expect(cloud.email, isNull);
      expect(cloud.autoBackup, isFalse);
      expect(drive.files.length, 1);
    },
  );

  group('backing up', () {
    setUp(() => cloud.signIn());

    test('uploads the whole backup and remembers when', () async {
      expect((await cloud.backupNow()).status, BackupStatus.done);
      expect(drive.files.length, 1);
      expect(drive.files.values.single.content, contains('"habits"'));
      expect(cloud.lastBackupAt, now);
    });

    test('on mobile data with Wi-Fi only on, an automatic backup waits; a manual one goes ahead after saying so', () async {
      net.wifi = false;
      expect(
        (await cloud.backupNow(automatic: true)).status,
        BackupStatus.waitingForWifi,
      );
      expect(drive.files, isEmpty);
      expect(
        (await cloud.backupNow()).status,
        BackupStatus.waitingForWifi,
        reason: 'manual stops too unless allowed',
      );
      expect(
        (await cloud.backupNow(overrideWifiOnly: true)).status,
        BackupStatus.done,
      );
    });

    test('Wi-Fi only off lets it use mobile data', () async {
      net.wifi = false;
      wifiOnly = false;
      expect((await cloud.backupNow()).status, BackupStatus.done);
    });

    test('offline is reported as offline', () async {
      net.online = false;
      net.wifi = false;
      expect((await cloud.backupNow()).status, BackupStatus.offline);
    });

    test('a refused token asks to sign in again, and keeps the old last-backup time', () async {
      await cloud.backupNow();
      final before = cloud.lastBackupAt;
      now = now.add(const Duration(days: 2));
      drive.failWith = 401;
      final r = await cloud.backupNow();
      expect(r.status, BackupStatus.signInNeeded);
      expect(cloud.lastBackupAt, before);
    });

    test('another Drive failure is reported with its message', () async {
      drive.failWith = 403;
      final r = await cloud.backupNow();
      expect(r.status, BackupStatus.failed);
      expect(r.message, isNotEmpty);
    });

    test('signed out is reported as sign-in needed', () async {
      auth.signedIn = false;
      expect((await cloud.backupNow()).status, BackupStatus.signInNeeded);
    });
  });

  group('restoring', () {
    setUp(() => cloud.signIn());

    test('fetches the stored backup, previews it, and restores it', () async {
      await cloud.backupNow();
      await repo.deleteHabit('a');
      final f = await cloud.fetchForRestore();
      expect(f, isNotNull);
      expect(f!.preview.habits, 1);
      await cloud.restore(f.text);
      expect((await repo.habits()).map((h) => h.id), ['a']);
      expect(settings.streakThreshold, 80);
    });

    test(
      'a restore waits for Wi-Fi when the setting says so, unless allowed',
      () async {
        await cloud.backupNow();
        net.wifi = false;
        await expectLater(
          cloud.fetchForRestore(),
          throwsA(isA<DriveException>()),
        );
        expect(await cloud.fetchForRestore(overrideWifiOnly: true), isNotNull);
      },
    );

    test(
      'says there is nothing to restore when nothing was ever uploaded',
      () async {
        expect(await cloud.fetchForRestore(), isNull);
      },
    );

    test('a damaged file on Drive is refused and nothing changes', () async {
      drive.files['x'] = (
        name: driveFileName,
        content: 'garbage',
        modified: now,
      );
      await expectLater(cloud.fetchForRestore(), throwsFormatException);
      expect((await repo.habits()).length, 1);
    });
  });

  group('automatic backup', () {
    setUp(() async {
      await cloud.signIn();
      await cloud.setAutoBackup(true);
    });

    test('runs when it was never done, then not again within a day', () async {
      await cloud.autoBackupIfDue();
      expect(drive.files.length, 1);
      final uploads = drive.requests.where((r) => r.startsWith('PATCH')).length;
      now = now.add(const Duration(hours: 5));
      await cloud.autoBackupIfDue();
      expect(
        drive.requests.where((r) => r.startsWith('PATCH')).length,
        uploads,
      );
      now = now.add(const Duration(hours: 20));
      await cloud.autoBackupIfDue();
      expect(
        drive.requests.where((r) => r.startsWith('PATCH')).length,
        uploads + 1,
      );
    });

    test('does nothing when switched off or signed out', () async {
      await cloud.setAutoBackup(false);
      await cloud.autoBackupIfDue();
      expect(drive.files, isEmpty);
    });

    test('does nothing when the account was removed even if the switch is still on', () async {
      await prefs.remove('cloud.email');
      await cloud.autoBackupIfDue();
      expect(drive.files, isEmpty);
    });

    test(
      'does nothing when the database cannot be read, and does not throw',
      () async {
        final broken = await openAppDatabase(
          databaseFactoryFfi,
          inMemoryDatabasePath,
        );
        await broken.close();
        final safety = await Directory.systemTemp.createTemp('dt_cloud2_');
        addTearDown(() => safety.delete(recursive: true));
        final c = CloudBackup(
          auth: auth,
          drive: DriveBackup(auth, MockClient(drive.handle)),
          backup: BackupService(
            repo: HabitRepository(broken),
            readSettings: () => settings,
            applySettings: (_) async {},
            safetyDir: () async => safety,
            now: () => now,
            appVersion: () async => '2.0.0',
          ),
          network: net,
          prefs: prefs,
          now: () => now,
          wifiOnly: () => wifiOnly,
        );
        await c.autoBackupIfDue();
        expect(drive.files, isEmpty);
      },
    );

    test('does nothing when there are no habits yet (nothing to protect, and it would overwrite a good backup)', () async {
      await repo.deleteHabit('a');
      await cloud.autoBackupIfDue();
      expect(drive.files, isEmpty);
    });

    test('never throws: a failure just waits for the next time', () async {
      drive.failWith = 503;
      await cloud.autoBackupIfDue();
      expect(cloud.lastBackupAt, isNull);
    });
  });
}
