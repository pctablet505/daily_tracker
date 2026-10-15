import 'dart:convert';
import 'dart:io';

import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/services/photo_store.dart';
import 'package:daily_tracker/state/actions.dart';
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

  test('the last restore can be undone, and the undo can be undone', () async {
    await seed();
    final text = (await service.export()).text;
    await repo.addHabit(habit('mine'));
    expect(await service.hasSafetyCopy(), isFalse);

    await service.restore(text);
    expect((await repo.habits()).map((h) => h.id), isNot(contains('mine')));
    expect(await service.hasSafetyCopy(), isTrue);

    await service.undoLastRestore();
    expect((await repo.habits()).map((h) => h.id), contains('mine'));

    await service.undoLastRestore();
    expect((await repo.habits()).map((h) => h.id), isNot(contains('mine')));
  });

  test('undoing with no safety copy says so and changes nothing', () async {
    await seed();
    await expectLater(service.undoLastRestore(), throwsFormatException);
    expect((await repo.habits()).length, 2);
  });

  test('the copy just made survives when older copies have later dates in their names', () async {
    await seed();
    for (final day in ['2027-01-01', '2027-01-02', '2027-01-03']) {
      File(p.join(safety.path, 'before-restore-${day}T00-00-00-000Z.json'))
          .writeAsStringSync('{}');
    }
    await repo.addHabit(habit('mine'));
    await service.restore((await service.export()).text);
    final names = safety.listSync().map((f) => p.basename(f.path)).toList();
    expect(names.where((n) => n.contains('2026-10-11')), hasLength(1));
    expect(names, hasLength(3));
    await service.undoLastRestore();
    expect((await repo.habits()).map((h) => h.id), contains('mine'));
  });

  test('undo puts back the copy made last, even when the clock was ahead for an older one', () async {
    var clock = now.add(const Duration(days: 9));
    final s = BackupService(
      repo: repo,
      readSettings: () => settings,
      applySettings: (_) async {},
      safetyDir: () async => safety,
      now: () => clock,
      appVersion: () async => '2.0.0',
    );
    await seed();
    final text = (await s.export()).text;
    await repo.addHabit(habit('older'));
    await s.restore(text);
    for (final f in safety.listSync().whereType<File>()) {
      f.setLastModifiedSync(DateTime.now().add(const Duration(days: 9)));
    }
    clock = now;
    await repo.addHabit(habit('newer'));
    await s.restore(text);

    await s.undoLastRestore();
    expect(
      (await repo.habits()).map((h) => h.id),
      allOf(contains('newer'), isNot(contains('older'))),
    );
  });

  test('restores made in the same second each keep their own copy', () async {
    await seed();
    final text = (await service.export()).text;
    await repo.addHabit(habit('first'));
    await service.restore(text);
    await repo.addHabit(habit('second'));
    await service.restore(text);
    expect(safety.listSync().whereType<File>(), hasLength(2));

    await service.undoLastRestore();
    expect((await repo.habits()).map((h) => h.id), contains('second'));
  });

  test(
    'pruning keeps the three copies made last, whatever their times',
    () async {
      await seed();
      final text = (await service.export()).text;
      for (var i = 0; i < 5; i++) {
        await repo.addHabit(habit('v$i'));
        await service.restore(text);
      }
      final kept = [
        for (final f in safety.listSync().whereType<File>())
          decodeBackup(f.readAsStringSync()).snapshot.habits
              .map((h) => h.id)
              .where((id) => id.startsWith('v'))
              .single,
      ]..sort();
      expect(kept, ['v2', 'v3', 'v4']);
    },
  );

  test(
    'when the newest safety copy is damaged, undo says so and changes nothing',
    () async {
      await seed();
      final text = (await service.export()).text;
      await repo.addHabit(habit('first'));
      await service.restore(text);
      final before = safety.listSync().map((f) => f.path).toSet();
      await repo.addHabit(habit('second'));
      await service.restore(text);
      final newest = safety.listSync().whereType<File>().singleWhere(
        (f) => !before.contains(f.path),
      );

      for (final damage in [
        utf8.encode('{corrupt'),
        [0xff, 0xfe, 0x00],
      ]) {
        newest.writeAsBytesSync(damage);
        await expectLater(
          service.undoLastRestore(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('damaged'),
            ),
          ),
        );
        expect((await repo.habits()).map((h) => h.id).toSet(), {'a', 's'});
      }
    },
  );

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
        csvRow(['=SUM(A1)', '+1', '-2', '@x', '\t=1', 'ok']),
        "'=SUM(A1),'+1,'-2,'@x,'\t=1,ok",
      );
    });

    test('a formula behind leading spaces is neutralised too', () {
      expect(
        csvRow([' =CMD()', '   +1', ' @x', ' plain', 'a =b']),
        "' =CMD(),'   +1,' @x, plain,a =b",
      );
    });
  });

  test(
    'exported files are named for the local date, not the UTC one',
    () async {
      for (final local in [
        DateTime(2026, 10, 12, 0, 30),
        DateTime(2026, 10, 12, 23, 30),
      ]) {
        final s = BackupService(
          repo: repo,
          readSettings: () => settings,
          applySettings: (_) async {},
          safetyDir: () async => safety,
          now: () => local,
          appVersion: () async => '2.0.0',
        );
        expect(
          (await s.export()).fileName,
          'daily-tracker-backup-2026-10-12.json',
        );
        expect(
          (await s.exportCsv()).fileName,
          'daily-tracker-entries-2026-10-12.csv',
        );
      }
    },
  );

  group('photos', () {
    late Directory media;
    late HabitActions actions;
    late BackupService sweeping;

    setUp(() async {
      media = await Directory.systemTemp.createTemp('dt_media_');
      addTearDown(() => media.delete(recursive: true));
      late final BackupService s;
      actions = HabitActions(
        repo: repo,
        photos: DiskPhotoStore(media),
        now: () => now,
        newId: () => 'x',
        keptBySafetyCopies: () => s.photosInSafetyCopies(),
      );
      s = BackupService(
        repo: repo,
        readSettings: () => settings,
        applySettings: (_) async {},
        safetyDir: () async => safety,
        now: () => now,
        appVersion: () async => '2.0.0',
        sweepPhotos: actions.sweepOrphanPhotos,
      );
      sweeping = s;
    });

    File photo(String name, {Duration age = const Duration(days: 1)}) =>
        File(p.join(media.path, name))
          ..writeAsBytesSync([1])
          ..setLastModifiedSync(now.subtract(age));

    Future<void> withPhoto(String name) async {
      await repo.addHabit(habit('p', logType: LogType.photo));
      await repo.setEntry(entry('p', mon).copyWith(photoPath: () => name));
    }

    String backupOf(List<Entry> entries) => encodeBackup(
      Snapshot(
        habits: [habit('p', logType: LogType.photo)],
        entries: entries,
        seenDays: const {},
      ),
      now: now,
      appVersion: '2.0.0',
    );

    test('the safety copies name the photos they refer to; a damaged copy makes that unknown', () async {
      await withPhoto('mine.jpg');
      await service.restore(backupOf(const []));
      expect(await service.photosInSafetyCopies(), {'mine.jpg'});
      File(p.join(safety.path, 'before-restore-2020-01-01T00-00-00-000Z.json'))
          .writeAsStringSync('{"format": "daily-tracker-backup"');
      expect(await service.photosInSafetyCopies(), isNull);
    });

    test('a restore removes stored photos that neither the restored data nor a safety copy refers to', () async {
      await withPhoto('mine.jpg');
      final mine = photo('mine.jpg');
      final stray = photo('stray.jpg');
      final fresh = photo('fresh.jpg', age: const Duration(minutes: 5));
      final restored = photo('restored.jpg');
      final text = backupOf([
        entry('p', tue).copyWith(photoPath: () => 'restored.jpg'),
      ]);

      await sweeping.restore(text);
      expect(stray.existsSync(), isFalse);
      expect(
        (mine.existsSync(), fresh.existsSync(), restored.existsSync()),
        (true, true, true),
        reason: 'Undo needs mine; fresh may be for an entry being saved',
      );

      // Three more restores push out the copy that still refers to mine.
      for (var i = 0; i < 3; i++) {
        await sweeping.restore(text);
      }
      expect(mine.existsSync(), isFalse);
      expect(restored.existsSync(), isTrue);
    });

    test('a restore removes no photo while a safety copy is damaged', () async {
      final stray = photo('stray.jpg');
      File(p.join(safety.path, 'before-restore-2020-01-01T00-00-00-000Z.json'))
          .writeAsStringSync('not json');
      await sweeping.restore(backupOf(const []));
      expect(stray.existsSync(), isTrue);
    });

    test('a photo replaced after a restore is still there when the restore is undone', () async {
      await withPhoto('mine.jpg');
      final mine = photo('mine.jpg');
      // An older backup from this phone, with the same photo.
      await sweeping.restore(
        backupOf([entry('p', mon).copyWith(photoPath: () => 'mine.jpg')]),
      );
      final camera = await Directory.systemTemp.createTemp('dt_camera_');
      addTearDown(() => camera.delete(recursive: true));
      final taken = File(p.join(camera.path, 'taken.jpg'))
        ..writeAsBytesSync([2]);
      await actions.logPhoto((await repo.habits()).single, mon, taken.path);
      expect(mine.existsSync(), isTrue, reason: 'replaced');
      await actions.finishDelete(await actions.deleteHabit('p'));
      expect(mine.existsSync(), isTrue, reason: 'deleted with its habit');

      await sweeping.undoLastRestore();
      expect((await repo.entries()).single.photoPath, 'mine.jpg');
      expect(mine.existsSync(), isTrue);
    });
  });
}
