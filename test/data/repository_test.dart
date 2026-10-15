import 'dart:io';

import 'package:daily_tracker/core/day_key.dart';
import 'package:daily_tracker/data/backup_codec.dart';
import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:daily_tracker/services/backup_service.dart';
import 'package:daily_tracker/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late Database db;
  late HabitRepository repo;
  late int changes;

  setUp(() async {
    db = await openAppDatabase(factory, inMemoryDatabasePath);
    changes = 0;
    repo = HabitRepository(db, onChanged: () => changes++);
    addTearDown(db.close);
  });

  group('habits', () {
    test(
      'a new habit is stored with the next sort position and read back whole',
      () async {
        final a = await repo.addHabit(
          habit('a', area: 'Health', logType: LogType.number, goal: 8),
        );
        final b = await repo.addHabit(habit('b'));
        expect((a.sortOrder, b.sortOrder), (0, 1));
        final all = await repo.habits();
        expect(all, [a, b]);
        expect(all.first.goal, 8.0);
        expect(all.first.logType, LogType.number);
      },
    );

    test('update changes the stored habit and reconciles entry states when goal or logType changes', () async {
      final a = await repo.addHabit(
        habit('a', logType: LogType.number, goal: 8),
      );
      await repo.setEntry(entry('a', mon, EntryState.partial, 4));
      await repo.setEntry(entry('a', tue, EntryState.done, 8));
      await repo.updateHabit(
        a.copyWith(name: 'Renamed', reminderMinutes: () => 480, goal: () => 4),
      );
      final back = (await repo.habits()).single;
      expect((back.name, back.reminderMinutes), ('Renamed', 480));
      expect(
        (await repo.entries(habitId: 'a', from: mon, to: mon)).single.state,
        EntryState.done,
      );
      await repo.updateHabit(back.copyWith(goal: () => 10));
      expect(
        (await repo.entries(habitId: 'a', from: tue, to: tue)).single.state,
        EntryState.partial,
      );
      expect(() => repo.updateHabit(habit('nope')), throwsStateError);
    });

    test(
      'an edit that leaves the grading alone keeps an un-ticked day partial',
      () async {
        final a = await repo.addHabit(habit('a', logType: LogType.photo));
        // Un-ticking a done day keeps its photo on a partial entry.
        final unticked = entry(
          'a',
          mon,
          EntryState.partial,
        ).copyWith(photoPath: () => 'a.jpg');
        await repo.setEntry(unticked);
        await repo.updateHabit(
          a.copyWith(
            name: 'Renamed',
            description: () => 'why',
            daysMask: Habit.weekdaysOnly,
            dayPart: DayPart.morning,
            reminderMinutes: () => 480,
            area: () => 'Health',
          ),
        );
        expect((await repo.habits()).single.name, 'Renamed');
        expect(await repo.entries(), [unticked]);
      },
    );

    // A number habit with 4 of its goal of 8 logged, edited three ways that
    // each stop the goal from grading it.
    final number = habit('a', logType: LogType.number, goal: 8);
    for (final c in [
      ('log type', number, number.copyWith(logType: LogType.tick)),
      ('kind', number, number.copyWith(kind: HabitKind.avoid)),
      (
        'avoid mode',
        number.copyWith(kind: HabitKind.avoid, avoidMode: AvoidMode.confirm),
        number.copyWith(kind: HabitKind.avoid, avoidMode: AvoidMode.track),
      ),
    ]) {
      test('a change of ${c.$1} grades the entries again', () async {
        await repo.addHabit(c.$2);
        await repo.setEntry(entry('a', mon, EntryState.partial, 4));
        await repo.updateHabit(c.$3);
        expect((await repo.entries()).single.state, EntryState.done);
      });
    }

    test('a stay-clear habit still marked as a number counts its kept days as done', () async {
      // A backup can hold this mix; the form never makes it.
      final s = await repo.addHabit(
        stayClear('s').copyWith(logType: LogType.number, goal: () => 10),
      );
      await repo.setEntry(entry('s', mon, EntryState.partial, 3));
      await repo.setEntry(entry('s', tue, EntryState.done, 3));
      await repo.updateHabit(s.copyWith(goal: () => 12));
      expect(
        [for (final e in await repo.entries()) e.state],
        [EntryState.done, EntryState.done],
      );
    });

    test('a new habit still goes last when the highest sort position is at the limit', () async {
      await db.insert('habits', {
        ...habit('top').toMap(),
        'sortOrder': 9223372036854775807,
      });
      await repo.addHabit(habit('new', created: tue));
      expect((await repo.habits()).map((h) => h.id), ['top', 'new']);
    });

    test('a batch of habits goes after the ones there, in its order, as one change', () async {
      await repo.addHabit(habit('a'));
      changes = 0;
      final added = await repo.addHabits([habit('b'), habit('c')]);
      expect(added.map((h) => h.sortOrder), [1, 2]);
      expect((await repo.habits()).map((h) => h.id), ['a', 'b', 'c']);
      expect(changes, 1);
    });

    test('a batch that fails part way stores none of it', () async {
      await repo.addHabit(habit('a'));
      changes = 0;
      await expectLater(
        repo.addHabits([habit('b'), habit('a')]),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.habits()).map((h) => h.id), ['a']);
      expect(changes, 0);
    });

    test(
      'a batch still goes last when the highest sort position is at the limit',
      () async {
        await db.insert('habits', {
          ...habit('top').toMap(),
          'sortOrder': 9223372036854775807,
        });
        await repo.addHabits([
          habit('new', created: tue),
          habit('newer', created: wed),
        ]);
        expect((await repo.habits()).map((h) => h.id), ['top', 'new', 'newer']);
      },
    );

    test('reorder renumbers by the given order and keeps any omitted habits after without colliding', () async {
      for (final id in ['a', 'b', 'c']) {
        await repo.addHabit(habit(id));
      }
      await repo.reorder(['c', 'a']);
      final all = await repo.habits();
      expect(all.map((h) => h.id), ['c', 'a', 'b']);
      expect(all.map((h) => h.sortOrder), [0, 1, 2]);
    });

    test(
      'archive ends the habit on the given day and keeps its entries',
      () async {
        await repo.addHabit(habit('a'));
        await repo.setEntry(entry('a', mon));
        await repo.archive('a', tue);
        final h = (await repo.habits()).single;
        expect((h.isArchived, h.endDay), (true, tue));
        expect((await repo.entries()).length, 1);
      },
    );

    test('start again makes a new habit from an archived one and keeps the old history', () async {
      final old = await repo.addHabit(habit('a', area: 'Mind'));
      await repo.setEntry(entry('a', mon));
      await repo.archive('a', tue);
      final fresh = await repo.startAgain(
        old.copyWith(endDay: () => tue),
        newId: 'a2',
        today: sun,
      );
      expect(
        (fresh.id, fresh.createdDay, fresh.endDay, fresh.area),
        ('a2', sun, null, 'Mind'),
      );
      final all = await repo.habits();
      expect(all.map((h) => h.id).toSet(), {'a', 'a2'});
      expect((await repo.entries()).single.habitId, 'a');
    });

    test(
      'delete removes the habit and its entries; restore puts both back',
      () async {
        await repo.addHabit(habit('a'));
        await repo.addHabit(habit('b'));
        await repo.setEntry(entry('a', mon));
        await repo.setEntry(entry('a', tue));
        await repo.setEntry(entry('b', mon));

        final gone = await repo.deleteHabit('a');
        expect(gone.entries.length, 2);
        expect((await repo.habits()).map((h) => h.id), ['b']);
        expect((await repo.entries()).map((e) => e.habitId), ['b']);

        await repo.restoreHabit(gone);
        expect((await repo.habits()).map((h) => h.id), ['a', 'b']);
        expect((await repo.entries()).length, 3);
      },
    );

    test('an entry cannot point at a habit that does not exist', () async {
      expect(() => repo.setEntry(entry('ghost', mon)), throwsA(anything));
    });
  });

  group('entries', () {
    setUp(() async => repo.addHabit(habit('a')));

    test('one entry per habit per day: a second write replaces the first and returns it', () async {
      expect(
        await repo.setEntry(entry('a', mon, EntryState.partial, 2)),
        isNull,
      );
      final replaced = await repo.setEntry(entry('a', mon, EntryState.done, 8));
      expect(replaced?.state, EntryState.partial);
      final all = await repo.entries();
      expect(all.length, 1);
      expect((all.single.state, all.single.value), (EntryState.done, 8.0));
    });

    test(
      'clear removes it and hands it back; clearing nothing returns null',
      () async {
        await repo.setEntry(entry('a', mon));
        expect((await repo.clearEntry('a', mon))?.day, mon);
        expect(await repo.entries(), isEmpty);
        final before = changes;
        expect(await repo.clearEntry('a', mon), isNull);
        expect(changes, before, reason: 'clearing nothing changes nothing');
      },
    );

    test(
      'a range query is inclusive at both ends and ordered by day',
      () async {
        for (final d in [wed, mon, fri, tue]) {
          await repo.setEntry(entry('a', d));
        }
        final got = await repo.entries(from: tue, to: fri);
        expect(got.map((e) => e.day), [tue, wed, fri]);
      },
    );

    test('note and photo path are kept', () async {
      await repo.setEntry(
        Entry(
          habitId: 'a',
          day: mon,
          state: EntryState.done,
          note: 'ran 5k',
          photoPath: 'x.jpg',
          loggedAt: DateTime.utc(2026, 10, 5, 7),
        ),
      );
      final e = (await repo.entries()).single;
      expect((e.note, e.photoPath), ('ran 5k', 'x.jpg'));
    });
  });

  group('seen days', () {
    test(
      'marking is idempotent and reports whether anything was new',
      () async {
        expect(await repo.markSeen(mon), isTrue);
        expect(await repo.markSeen(mon), isFalse);
        expect(await repo.seenDays(), {mon});
      },
    );

    test('an already-seen day does not announce a change', () async {
      await repo.markSeen(mon);
      final before = changes;
      await repo.markSeen(mon);
      expect(changes, before);
    });
  });

  group('change notification', () {
    test('every write announces itself exactly once; reads do not', () async {
      await repo.addHabit(habit('a'));
      expect(changes, 1);
      await repo.setEntry(entry('a', mon));
      expect(changes, 2);
      await repo.clearEntry('a', mon);
      expect(changes, 3);
      await repo.reorder(['a']);
      expect(changes, 4);
      await repo.updateHabit(habit('a').copyWith(name: 'A2'));
      expect(changes, 5);
      await repo.archive('a', tue);
      expect(changes, 6);
      await repo.startAgain(habit('a'), newId: 'b', today: wed);
      expect(changes, 7);
      final gone = await repo.deleteHabit('b');
      expect(changes, 8);
      await repo.restoreHabit(gone);
      expect(changes, 9);
      await repo.replaceAll(await repo.snapshot());
      expect(changes, 10);
      changes = 4;
      await repo.habits();
      await repo.entries();
      await repo.seenDays();
      expect(changes, 4);
    });
  });

  group('snapshot', () {
    test(
      'round trips everything, including archived habits and seen days',
      () async {
        await repo.addHabit(habit('a'));
        await repo.addHabit(stayClear('s'));
        await repo.setEntry(entry('a', mon));
        await repo.setEntry(slip('s', tue));
        await repo.archive('s', wed);
        await repo.markSeen(mon);
        await repo.markSeen(tue);

        final snap = await repo.snapshot();
        expect(
          (snap.habits.length, snap.entries.length, snap.seenDays.length),
          (2, 2, 2),
        );

        final other = await openAppDatabase(factory, inMemoryDatabasePath);
        addTearDown(other.close);
        final repo2 = HabitRepository(other);
        await repo2.replaceAll(snap);
        expect(await repo2.habits(), await repo.habits());
        expect(await repo2.entries(), await repo.entries());
        expect(await repo2.seenDays(), await repo.seenDays());
      },
    );

    test('replace discards what was there before', () async {
      await repo.addHabit(habit('old'));
      await repo.setEntry(entry('old', mon));
      await repo.markSeen(tue);
      await repo.replaceAll(
        Snapshot(habits: [habit('new')], entries: const [], seenDays: {wed}),
      );
      expect((await repo.habits()).map((h) => h.id), ['new']);
      expect(await repo.entries(), isEmpty);
      expect(await repo.seenDays(), {wed});
    });

    group('is refused, and the current data kept, when', () {
      Future<void> expectRefused(Snapshot bad) async {
        await repo.addHabit(habit('keep'));
        await repo.setEntry(entry('keep', mon));
        await expectLater(repo.replaceAll(bad), throwsFormatException);
        expect((await repo.habits()).map((h) => h.id), ['keep']);
        expect((await repo.entries()).length, 1);
      }

      test('an entry names a habit that is not in the file', () async {
        await expectRefused(
          Snapshot(
            habits: [habit('a')],
            entries: [entry('b', mon)],
            seenDays: const {},
          ),
        );
      });

      test('two habits share an id', () async {
        await expectRefused(
          Snapshot(
            habits: [habit('a'), habit('a')],
            entries: const [],
            seenDays: const {},
          ),
        );
      });

      test('two entries are for the same habit and day', () async {
        await expectRefused(
          Snapshot(
            habits: [habit('a')],
            entries: [entry('a', mon), entry('a', mon, EntryState.skipped)],
            seenDays: const {},
          ),
        );
      });
    });
  });

  group('a database an older version wrote', () {
    // 2.0.2 stored these values from backups it accepted; 2.0.3 refuses them in
    // a backup, but a phone that updated still holds them.
    Future<void> seedOld() async {
      Future<void> add(Habit h, Map<String, Object?> odd) =>
          db.insert('habits', {...h.toMap(), ...odd});
      await add(habit('top'), {'sortOrder': 9223372036854775807});
      await add(habit('bottom'), {'sortOrder': -9223372036854775807});
      await add(habit('zero', logType: LogType.number), {'goal': 0});
      await add(habit('below', logType: LogType.number), {'goal': -2.5});
      await add(habit('none'), {'daysMask': 0});
      await add(habit('wide'), {'daysMask': 200});
      await add(habit('early', created: fri), {'endDay': mon.toString()});
      await add(habit('late'), {'reminderMinutes': 9223372036854775807});
      await add(habit('negative'), {'reminderMinutes': -5});
      Future<void> log(Entry e, Map<String, Object?> odd) =>
          db.insert('entries', {...e.toMap(), ...odd});
      await log(entry('zero', mon), {'value': -4});
      await log(entry('top', mon), {'photoPath': 'a:b.jpg'});
      await log(entry('top', tue), {'photoPath': ' p.jpg'});
      await log(entry('top', wed), {'loggedAt': 'yesterday'});
    }

    setUp(seedOld);

    test('loads, with each odd value mended', () async {
      final h = {for (final x in await repo.habits()) x.id: x};
      expect(h, hasLength(9));
      expect(h['top']!.sortOrder, 0x1fffffffffffff);
      expect(h['bottom']!.sortOrder, -0x1fffffffffffff);
      expect((h['zero']!.goal, h['below']!.goal), (null, null));
      expect((h['none']!.daysMask, h['wide']!.daysMask), (127, 200 & 127));
      expect(h['early']!.endDay, thu);
      expect(h['late']!.reminderMinutes, isNull);
      expect(h['negative']!.reminderMinutes, isNull);

      final e = {for (final x in await repo.entries()) (x.habitId, x.day): x};
      expect(e, hasLength(4));
      expect(e[('zero', mon)]!.value, isNull);
      expect(e[('zero', mon)]!.state, EntryState.done);
      expect(e[('top', mon)]!.photoPath, isNull);
      expect(e[('top', tue)]!.photoPath, isNull);
      expect(e[('top', wed)]!.loggedAt, DateTime.utc(2026, 10, 7));
    });

    test(
      'a snapshot reads and makes a backup this version takes back',
      () async {
        final snap = await repo.snapshot();
        expect((snap.habits.length, snap.entries.length), (9, 4));
        final again = decodeBackup(
          encodeBackup(snap, now: DateTime.utc(2026, 10, 11), appVersion: 'x'),
        ).snapshot;
        expect(again.habits, snap.habits);
        expect(again.entries, snap.entries);
      },
    );

    test('every write that reads a row first still works', () async {
      await repo.updateHabit((await repo.habits()).first);
      expect(await repo.setEntry(entry('zero', mon)), isNotNull);
      expect(await repo.clearEntry('top', mon), isNotNull);
      final gone = await repo.deleteHabit('early');
      expect(gone.habit.endDay, thu);
    });

    test('a clean backup can be restored over it', () async {
      final safety = await Directory.systemTemp.createTemp('dt_safe_');
      addTearDown(() => safety.delete(recursive: true));
      final service = BackupService(
        repo: repo,
        readSettings: () => const Settings(),
        applySettings: (_) async {},
        safetyDir: () async => safety,
        now: () => DateTime.utc(2026, 10, 11, 12),
        appVersion: () async => '2.0.3',
      );
      final clean = encodeBackup(
        Snapshot(habits: [habit('fresh')], entries: const [], seenDays: {mon}),
        now: DateTime.utc(2026, 10, 11),
        appVersion: '2.0.3',
      );
      await service.restore(clean);
      expect((await repo.habits()).map((h) => h.id), ['fresh']);
      await service.undoLastRestore();
      expect(await repo.habits(), hasLength(9));
    });
  });

  group('a database holding days before 1970', () {
    // 2.0.2 and 2.0.3 took such days in from a crafted backup. This version
    // refuses them in a backup, so they must not reach one.
    const first = DayKey(1970, 1, 1);
    final old = habit(
      'old',
      created: const DayKey(1960, 3, 1),
      logType: LogType.number,
      goal: 8,
    );

    setUp(() async {
      await db.insert('habits', old.toMap());
      await db.insert(
        'habits',
        habit(
          'gone',
          created: const DayKey(1950, 1, 1),
          end: const DayKey(1955, 1, 1),
        ).toMap(),
      );
      for (final e in [
        entry('old', const DayKey(1960, 3, 1), EntryState.partial, 4),
        entry('old', const DayKey(1969, 12, 31), EntryState.partial, 5),
        entry('gone', const DayKey(1950, 6, 1)),
      ]) {
        await db.insert('entries', e.toMap());
      }
      for (final d in ['1960-03-01', '1969-12-31', '1970-01-01']) {
        await db.insert('seen_days', {'day': d});
      }
    });

    test('reads them as 1970-01-01, keeping the later of two entries that meet there', () async {
      final h = {for (final x in await repo.habits()) x.id: x};
      expect((h['old']!.createdDay, h['old']!.endDay), (first, null));
      // Ended before 1970: it stays ended, the day before its start.
      expect(
        (h['gone']!.createdDay, h['gone']!.endDay),
        (first, first.addDays(-1)),
      );
      final entries = [
        entry('gone', first),
        entry('old', first, EntryState.partial, 5),
      ];
      expect(await repo.entries(), entries);
      expect(await repo.seenDays(), {first});
      final snap = await repo.snapshot();
      expect(snap.habits, await repo.habits());
      expect(snap.entries, entries);
      expect(snap.seenDays, {first});
    });

    test('a backup made from it is taken back', () async {
      final snap = await repo.snapshot();
      final again = decodeBackup(
        encodeBackup(snap, now: DateTime.utc(2026, 10, 11), appVersion: 'x'),
      ).snapshot;
      expect(again.habits, snap.habits);
      expect(again.entries, snap.entries);
      expect(again.seenDays, snap.seenDays);
    });

    test('a restore over it can be undone', () async {
      final safety = await Directory.systemTemp.createTemp('dt_safe_');
      addTearDown(() => safety.delete(recursive: true));
      final service = BackupService(
        repo: repo,
        readSettings: () => const Settings(),
        applySettings: (_) async {},
        safetyDir: () async => safety,
        now: () => DateTime.utc(2026, 10, 11, 12),
        appVersion: () async => '2.0.3',
      );
      final before = await repo.snapshot();
      await service.restore(
        encodeBackup(
          Snapshot(
            habits: [habit('fresh')],
            entries: const [],
            seenDays: {mon},
          ),
          now: DateTime.utc(2026, 10, 11),
          appVersion: '2.0.3',
        ),
      );
      await service.undoLastRestore();
      final after = await repo.snapshot();
      expect(after.habits, before.habits);
      expect(after.entries, before.entries);
    });

    test('a change of goal grades the entries stored before 1970', () async {
      await repo.updateHabit(
        (await repo.habits())
            .firstWhere((h) => h.id == 'old')
            .copyWith(goal: () => 5),
      );
      final kept = (await repo.entries(habitId: 'old')).single;
      expect((kept.day, kept.state), (first, EntryState.done));
    });
  });

  group('opening the database', () {
    test(
      'removes the old app database files and starts a new empty one',
      () async {
        final dir = await Directory.systemTemp.createTemp('dt_db_');
        addTearDown(() => dir.delete(recursive: true));
        for (final name in [
          'daily_tracker.db',
          'daily_tracker.db-journal',
          'daily_tracker.db-wal',
          'daily_tracker.db-shm',
        ]) {
          File(p.join(dir.path, name)).writeAsStringSync('old');
        }
        final db = await openAppDatabase(
          factory,
          p.join(dir.path, 'habits.db'),
          removeLegacyIn: dir.path,
        );
        addTearDown(db.close);
        expect(
          Directory(dir.path)
              .listSync()
              .map((f) => p.basename(f.path))
              .where((n) => n.startsWith('daily_tracker')),
          isEmpty,
        );
        expect(await HabitRepository(db).habits(), isEmpty);
      },
    );

    test(
      'a separate connection can be closed without closing the app\'s own',
      () async {
        final dir = await Directory.systemTemp.createTemp('dt_db_');
        addTearDown(() => dir.delete(recursive: true));
        final path = p.join(dir.path, 'habits.db');
        final appDb = await openAppDatabase(factory, path);
        addTearDown(appDb.close);
        await HabitRepository(appDb).addHabit(habit('a'));

        final own = await openAppDatabase(factory, path, singleInstance: false);
        expect((await HabitRepository(own).habits()).map((h) => h.id), ['a']);
        await own.close();

        expect(appDb.isOpen, isTrue);
        expect((await HabitRepository(appDb).habits()).map((h) => h.id), ['a']);
      },
    );

    test('keeps the new database when it is opened a second time', () async {
      final dir = await Directory.systemTemp.createTemp('dt_db_');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'habits.db');
      var db = await openAppDatabase(factory, path, removeLegacyIn: dir.path);
      await HabitRepository(db).addHabit(habit('a'));
      await db.close();
      db = await openAppDatabase(factory, path, removeLegacyIn: dir.path);
      addTearDown(db.close);
      expect((await HabitRepository(db).habits()).map((h) => h.id), ['a']);
    });
  });
}
