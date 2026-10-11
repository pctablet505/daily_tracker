// Regression tests for defects found in review. Each test states the behaviour the app
// promises; a red result is a finding.
import 'dart:convert';
import 'dart:io';

import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/data/stats.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/services/reminder_plan.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

Map<String, Object?> _backupWith({
  Map<String, Object?> habitExtra = const {},
  Map<String, Object?> entryExtra = const {},
}) {
  final h = habit('a', logType: LogType.photo).toMap()..addAll(habitExtra);
  final e = Entry(
    habitId: 'a',
    day: sat,
    state: EntryState.done,
    photoPath: 'p1.jpg',
    loggedAt: DateTime.utc(2026, 10, 10),
  ).toMap()..addAll(entryExtra);
  return {
    'format': backupFormat,
    'version': backupVersion,
    'exportedAt': '2026-10-11T00:00:00.000Z',
    'habits': [h],
    'entries': [e],
    'seenDays': <String>[],
  };
}

void main() {
  sqfliteFfiInit();

  test('a photo name that leaves the photo folder is refused at restore', () {
    final text = jsonEncode(_backupWith(entryExtra: {'photoPath': '../../x'}));
    expect(
      () => decodeBackup(text),
      throwsFormatException,
      reason: 'decodeBackup accepted photoPath "../../x"',
    );
  });

  test('a huge number in a backup is reported as damage (FormatException), not an UnsupportedError', () {
    final text = jsonEncode(_backupWith())
        .replaceFirst('"daysMask":127', '"daysMask":1e400');
    expect(text, contains('1e400'));
    expect(() => decodeBackup(text), throwsFormatException);
  });

  test('one restored habit with an absurd reminder time does not cancel every reminder', () {
    final text = jsonEncode(
      _backupWith(habitExtra: {'reminderMinutes': 1000000000000}),
    );
    final b = decodeBackup(text);
    final good = habit('g').copyWith(reminderMinutes: () => 8 * 60);
    final l = Ledger(habits: [...b.snapshot.habits, good], entries: const []);
    late List<PlannedReminder> plan;
    expect(
      () => plan = planReminders(
        l,
        settings: const Settings(eveningCheckInOn: false),
        now: DateTime(2026, 10, 11, 6),
        horizonDays: 14,
      ),
      returnsNormally,
    );
    expect(plan.where((r) => r.habitId == 'g'), hasLength(14));
  });

  test('a restore keeps its safety copy even when older copies carry later timestamps (clock was ahead)', () async {
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    final repo = HabitRepository(db);
    await repo.addHabit(habit('mine'));
    final safety = Directory.systemTemp.createTempSync('dt_review_safe_');
    addTearDown(() => safety.delete(recursive: true));
    for (final stamp in ['2027-01-01', '2027-01-02', '2027-01-03']) {
      File(p.join(safety.path, 'before-restore-${stamp}T00-00-00-000Z.json'))
          .writeAsStringSync('{}');
    }
    final service = BackupService(
      repo: repo,
      readSettings: () => const Settings(),
      applySettings: (_) async {},
      safetyDir: () async => safety,
      now: () => DateTime.utc(2026, 10, 11, 12),
      appVersion: () async => '2.0.0',
    );
    await service.restore(
      encodeBackup(
        const Snapshot(habits: [], entries: [], seenDays: {}),
        now: DateTime.utc(2026, 10, 1),
        appVersion: '2.0.0',
      ),
    );
    final names = safety.listSync().map((f) => p.basename(f.path)).toList();
    expect(
      names.where((n) => n.contains('2026-10-11')),
      hasLength(1),
      reason:
          'the copy of "mine" was deleted right after it was written: $names',
    );
  });
}
