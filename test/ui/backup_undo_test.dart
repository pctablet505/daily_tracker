import 'dart:io';

import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:daily_tracker/ui/screens/backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Database;

import 'harness.dart';

final class _NoDb extends Fake implements Database {}

void main() {
  setUpAll(loadAppFont);

  Future<void> pumpBackup(WidgetTester tester, Directory safety) async {
    final overrides = await baseOverrides(ledger: sampleLedger());
    overrides.add(
      backupServiceProvider.overrideWithValue(
        BackupService(
          repo: HabitRepository(_NoDb()),
          readSettings: () => const Settings(),
          applySettings: (_) async {},
          safetyDir: () async => safety,
          now: DateTime.now,
          appVersion: () async => '2.0.0',
        ),
      ),
    );
    await pumpScreen(tester, const BackupScreen(), overrides: overrides);
  }

  testWidgets(
    'there is nothing to undo until a restore has made a safety copy',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('dt_undo_ui_');
      addTearDown(() => dir.deleteSync(recursive: true));
      await pumpBackup(tester, dir);
      expect(find.text('Restore from a file'), findsOneWidget);
      expect(find.text('Undo the last restore'), findsNothing);
    },
  );

  testWidgets(
    'with a safety copy on the phone, the last restore can be undone',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('dt_undo_ui_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'before-restore-2026-10-11T00-00-00-000Z.json'))
          .writeAsStringSync('{}');
      await pumpBackup(tester, dir);
      expect(find.text('Undo the last restore'), findsOneWidget);
    },
  );
}
