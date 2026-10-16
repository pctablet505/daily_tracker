import 'dart:io';

import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/services/files.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:daily_tracker/ui/screens/backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Database;

import '../data/fixtures.dart';
import 'harness.dart';

final class _NoDb extends Fake implements Database {}

final class _OneFile implements FileService {
  _OneFile(this.text);
  final String text;
  @override
  Future<String?> pickAndReadText({int maxBytes = 20 * 1024 * 1024}) async =>
      text;
  @override
  Future<void> shareText(
    String fileName,
    String content, {
    String? subject,
    String mimeType = 'application/json',
  }) async {}
}

String _backupOfTwoHabits() => encodeBackup(
  Snapshot(
    habits: [habit('a'), habit('b')],
    entries: [entry('a', mon)],
    seenDays: const {},
  ),
  now: DateTime(2026, 10, 10, 8, 30),
  appVersion: '2.0.0',
);

/// File work needs real time: lets it finish, then settles.
Future<void> _letItRun(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFont);

  Future<void> pumpBackup(
    WidgetTester tester,
    Directory safety, {
    String? fileToRestore,
  }) async {
    final overrides = await baseOverrides(ledger: sampleLedger());
    if (fileToRestore != null) {
      overrides.add(
        fileServiceProvider.overrideWithValue(_OneFile(fileToRestore)),
      );
    }
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

  testWidgets(
    'the undo dialog says when the copy was made, what it holds, and that settings go back too',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('dt_undo_ui_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'before-restore-2026-10-10T08-30-00-000Z-n1.json'))
          .writeAsStringSync(_backupOfTwoHabits());
      await pumpBackup(tester, dir);
      await tester.tap(find.text('Undo the last restore'));
      await _letItRun(tester);
      final text = tester
          .widget<Text>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining('before the last restore'),
            ),
          )
          .data!;
      expect(text, contains('2 habits and 1 entry'));
      expect(text, contains('Sat 10 Oct'));
      expect(text, contains('reminder, streak and theme settings'));
    },
  );

  testWidgets(
    'a damaged safety copy is reported, and no undo is offered to confirm',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('dt_undo_ui_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'before-restore-2026-10-10T08-30-00-000Z-n1.json'))
          .writeAsStringSync('{corrupt');
      await pumpBackup(tester, dir);
      await tester.tap(find.text('Undo the last restore'));
      await _letItRun(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('is damaged'), findsOneWidget);
    },
  );

  testWidgets('the restore dialog says settings are replaced too', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('dt_undo_ui_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await pumpBackup(tester, dir, fileToRestore: _backupOfTwoHabits());
    await tester.tap(find.text('Restore from a file'));
    await _letItRun(tester);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(
          'Your current habits and history, and your reminder, streak and theme settings, are replaced.',
        ),
      ),
      findsOneWidget,
    );
  });
}
