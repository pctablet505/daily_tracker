import 'dart:async';

import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/services/files.dart';
import 'package:daily_tracker/state/services.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:daily_tracker/ui/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'harness.dart';

final class _NoDb extends Fake implements Database {}

/// Counts spreadsheet exports; each is ready at once.
final class _CountingBackup extends BackupService {
  _CountingBackup()
    : super(
        repo: HabitRepository(_NoDb()),
        readSettings: () => const Settings(),
        applySettings: (_) async {},
        safetyDir: () => throw UnimplementedError(),
        now: DateTime.now,
        appVersion: () async => '2.0.0',
      );
  int csvExports = 0;

  @override
  Future<ExportedFile> exportCsv() async {
    csvExports++;
    return const ExportedFile('entries.csv', 'habit\r\n');
  }
}

/// A share sheet that stays open until [close].
final class _SlowShare implements FileService {
  final _open = Completer<void>();
  void close() => _open.complete();
  @override
  Future<String?> pickAndReadText({int maxBytes = 20 * 1024 * 1024}) async =>
      null;
  @override
  Future<void> shareText(
    String fileName,
    String content, {
    String? subject,
    String mimeType = 'application/json',
  }) => _open.future;
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('quiet hours that start and end together say they are off', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const SettingsScreen(),
      overrides: await baseOverrides(
        ledger: sampleLedger(),
        prefs: {
          'quietHoursOn': true,
          'quietStartMinutes': 22 * 60,
          'quietEndMinutes': 22 * 60,
        },
      ),
    );
    expect(
      find.text('Quiet hours are off (start and end are the same)'),
      findsOneWidget,
    );
    expect(find.textContaining('No reminders from'), findsNothing);
  });

  testWidgets(
    'a second tap on spreadsheet export while one is open does nothing',
    (tester) async {
      final backup = _CountingBackup();
      final share = _SlowShare();
      final overrides = await baseOverrides(ledger: sampleLedger())
        ..add(backupServiceProvider.overrideWithValue(backup))
        ..add(fileServiceProvider.overrideWithValue(share));
      await pumpScreen(tester, const SettingsScreen(), overrides: overrides);
      final row = find.text('Export entries as a spreadsheet');
      await tester.scrollUntilVisible(row, 200);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(row.hitTestable(), findsOneWidget);
      await tester.tap(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();
      expect(backup.csvExports, 1);

      share.close();
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      expect(backup.csvExports, 2, reason: 'free again once the first is done');
    },
  );

  testWidgets('the App lock setting says what forgetting the PIN costs', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const SettingsScreen(),
      overrides: await baseOverrides(ledger: sampleLedger()),
    );
    expect(
      find.text(
        'If you forget the PIN and have no phone screen lock, the only way back is clearing the app\'s data.',
      ),
      findsOneWidget,
    );
  });
}
