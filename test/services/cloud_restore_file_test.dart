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

final class _Online implements NetworkInfo {
  @override
  Future<bool> isOnWifi() async => true;
  @override
  Future<bool> isOnline() async => true;
}

void main() {
  sqfliteFfiInit();

  test(
    'a restore downloads the file it found, even if another lands meanwhile',
    () async {
      final db = await openAppDatabase(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      addTearDown(db.close);
      final repo = HabitRepository(db);
      await repo.addHabit(habit('a'));
      SharedPreferences.setMockInitialValues({});
      final safety = await Directory.systemTemp.createTemp('dt_cloud_');
      addTearDown(() => safety.delete(recursive: true));
      final now = DateTime.utc(2026, 10, 11, 12);
      final drive = FakeDrive();
      final auth = FakeAuth();
      var armed = false;
      final cloud = CloudBackup(
        auth: auth,
        drive: DriveBackup(
          auth,
          MockClient((r) async {
            final res = await drive.handle(r);
            // Another phone uploads right after this one looked the file up.
            if (armed && r.method == 'GET' && r.url.path == '/drive/v3/files') {
              armed = false;
              drive.files['late'] = (
                name: driveFileName,
                content: 'not a backup',
                modified: now.add(const Duration(minutes: 1)),
              );
            }
            return res;
          }),
        ),
        backup: BackupService(
          repo: repo,
          readSettings: () => const Settings(),
          applySettings: (_) async {},
          safetyDir: () async => safety,
          now: () => now,
          appVersion: () async => '2.0.0',
        ),
        network: _Online(),
        prefs: await SharedPreferences.getInstance(),
        now: () => now,
        wifiOnly: () => false,
      );
      await cloud.backupNow();
      armed = true;

      final found = await cloud.fetchForRestore();
      expect(found!.preview.habits, 1);
      expect(found.modified, now);
    },
  );
}
