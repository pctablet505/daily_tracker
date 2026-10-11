import 'dart:io';

import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';

void main() {
  sqfliteFfiInit();
  late HabitRepository repo;
  late Directory safety;
  late BackupService service;
  var settings = const Settings(streakThreshold: 70);
  final now = DateTime.utc(2026, 10, 11, 12);

  setUp(() async {
    final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    repo = HabitRepository(db);
    safety = await Directory.systemTemp.createTemp('dt_safe_');
    addTearDown(() => safety.delete(recursive: true));
    settings = const Settings(streakThreshold: 70);
    service = BackupService(
      repo: repo,
      readSettings: () => settings,
      applySettings: (m) async => settings = settings.withImported(m),
      safetyDir: () async => safety,
      now: () => now,
      appVersion: () async => '2.0.0',
    );
  });

  Future<void> seed() async {
    await repo.addHabit(habit('a'));
    await repo.addHabit(stayClear('s'));
    await repo.setEntry(entry('a', mon));
    await repo.setEntry(slip('s', tue));
    await repo.markSeen(mon);
  }

  test('export contains everything and the exportable settings', () async {
    await seed();
    final e = await service.export();
    expect(e.fileName, 'daily-tracker-backup-2026-10-11.json');
    final back = decodeBackup(e.text);
    expect(
      (
        back.snapshot.habits.length,
        back.snapshot.entries.length,
        back.snapshot.seenDays.length,
      ),
      (2, 2, 1),
    );
    expect(back.settings['streakThreshold'], 70);
    expect(back.appVersion, '2.0.0');
  });

  test('previewing a backup counts what is in it', () async {
    await seed();
    final p = service.preview((await service.export()).text);
    expect((p.habits, p.entries), (2, 2));
    expect(p.exportedAt, now);
  });

  test(
    'previewing a damaged file throws a readable error and changes nothing',
    () async {
      await seed();
      expect(() => service.preview('{"nope":1}'), throwsFormatException);
      expect((await repo.habits()).length, 2);
    },
  );

  test('restore replaces everything and applies the settings', () async {
    await seed();
    final text = (await service.export()).text;
    await repo.deleteHabit('a');
    await repo.addHabit(habit('other'));
    settings = const Settings(streakThreshold: 30);

    await service.restore(text);
    expect((await repo.habits()).map((h) => h.id).toSet(), {'a', 's'});
    expect((await repo.entries()).length, 2);
    expect(await repo.seenDays(), {mon});
    expect(settings.streakThreshold, 70);
  });

  test('restore first saves what was on the phone, so a wrong restore can be undone', () async {
    await seed();
    final text = (await service.export()).text;
    await repo.addHabit(habit('mine'));
    await service.restore(text);
    final files = safety.listSync().whereType<File>().toList();
    expect(files.length, 1);
    expect(p.basename(files.single.path), startsWith('before-restore-'));
    final saved = decodeBackup(files.single.readAsStringSync());
    expect(saved.snapshot.habits.map((h) => h.id), contains('mine'));
  });

  test('only the three newest safety copies are kept', () async {
    await seed();
    final text = (await service.export()).text;
    for (var i = 0; i < 5; i++) {
      final s = BackupService(
        repo: repo,
        readSettings: () => settings,
        applySettings: (_) async {},
        safetyDir: () async => safety,
        now: () => now.add(Duration(minutes: i)),
        appVersion: () async => '2.0.0',
      );
      await s.restore(text);
    }
    final names = safety.listSync().map((f) => p.basename(f.path)).toList()
      ..sort();
    expect(names.length, 3);
    // the newest three restores: minutes 2, 3 and 4 after the first
    expect(names.map((n) => RegExp(r'T(\d\d)-(\d\d)').firstMatch(n)![2]), [
      '02',
      '03',
      '04',
    ]);
  });

  test('a bad file is refused before anything is touched or saved', () async {
    await seed();
    await expectLater(service.restore('garbage'), throwsFormatException);
    expect((await repo.habits()).length, 2);
    expect(safety.listSync(), isEmpty);
  });

  group('CSV export', () {
    test('one row per entry with a header, habits by name', () async {
      await seed();
      final csv = await service.exportCsv();
      final lines = csv.text.trim().split('\r\n');
      expect(lines.first, 'habit,kind,day,state,value,note');
      expect(lines.length, 3);
      expect(lines[1], 'Habit a,build,2026-10-05,done,,');
      expect(lines[2], 'Habit s,avoid,2026-10-06,slipped,,');
      expect(csv.fileName, 'daily-tracker-entries-2026-10-11.csv');
    });

    test('quotes commas, quotes and line breaks', () {
      final row = csvRow(['a,b', 'say "hi"', 'two\nlines', 'plain']);
      expect(row, '"a,b","say ""hi""","two\nlines",plain');
    });

    test('a cell that a spreadsheet would run as a formula is neutralised', () {
      expect(
        csvRow(['=SUM(A1)', '+1', '-2', '@x', '\t=1', 'ok', ' =not a formula']),
        "'=SUM(A1),'+1,'-2,'@x,'\t=1,ok, =not a formula",
      );
    });
  });
}
