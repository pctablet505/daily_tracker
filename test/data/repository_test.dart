import 'dart:io';

import 'package:daily_tracker/data/database.dart';
import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late HabitRepository repo;
  late int changes;

  setUp(() async {
    final db = await openAppDatabase(factory, inMemoryDatabasePath);
    changes = 0;
    repo = HabitRepository(db, onChanged: () => changes++);
    addTearDown(db.close);
  });

  group('habits', () {
    test('a new habit is stored with the next sort position and read back whole', () async {
      final a = await repo.addHabit(habit('a', area: 'Health', logType: LogType.number, goal: 8));
      final b = await repo.addHabit(habit('b'));
      expect((a.sortOrder, b.sortOrder), (0, 1));
      final all = await repo.habits();
      expect(all, [a, b]);
      expect(all.first.goal, 8.0);
      expect(all.first.logType, LogType.number);
    });

    test('update changes the stored habit; an unknown id is an error', () async {
      final a = await repo.addHabit(habit('a'));
      await repo.updateHabit(a.copyWith(name: 'Renamed', reminderMinutes: () => 480));
      final back = (await repo.habits()).single;
      expect((back.name, back.reminderMinutes), ('Renamed', 480));
      expect(() => repo.updateHabit(habit('nope')), throwsStateError);
    });

    test('reorder renumbers by the given order and leaves nothing out', () async {
      for (final id in ['a', 'b', 'c']) {
        await repo.addHabit(habit(id));
      }
      await repo.reorder(['c', 'a', 'b']);
      expect((await repo.habits()).map((h) => h.id), ['c', 'a', 'b']);
    });

    test('archive ends the habit on the given day and keeps its entries', () async {
      await repo.addHabit(habit('a'));
      await repo.setEntry(entry('a', mon));
      await repo.archive('a', tue);
      final h = (await repo.habits()).single;
      expect((h.isArchived, h.endDay), (true, tue));
      expect((await repo.entries()).length, 1);
    });

    test('start again makes a new habit from an archived one and keeps the old history', () async {
      final old = await repo.addHabit(habit('a', area: 'Mind'));
      await repo.setEntry(entry('a', mon));
      await repo.archive('a', tue);
      final fresh = await repo.startAgain(old.copyWith(endDay: () => tue), newId: 'a2', today: sun);
      expect((fresh.id, fresh.createdDay, fresh.endDay, fresh.area), ('a2', sun, null, 'Mind'));
      final all = await repo.habits();
      expect(all.map((h) => h.id).toSet(), {'a', 'a2'});
      expect((await repo.entries()).single.habitId, 'a');
    });

    test('delete removes the habit and its entries; restore puts both back', () async {
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
    });

    test('an entry cannot point at a habit that does not exist', () async {
      expect(() => repo.setEntry(entry('ghost', mon)), throwsA(anything));
    });
  });

  group('entries', () {
    setUp(() async => repo.addHabit(habit('a')));

    test('one entry per habit per day: a second write replaces the first and returns it', () async {
      expect(await repo.setEntry(entry('a', mon, EntryState.partial, 2)), isNull);
      final replaced = await repo.setEntry(entry('a', mon, EntryState.done, 8));
      expect(replaced?.state, EntryState.partial);
      final all = await repo.entries();
      expect(all.length, 1);
      expect((all.single.state, all.single.value), (EntryState.done, 8.0));
    });

    test('clear removes it and hands it back; clearing nothing returns null', () async {
      await repo.setEntry(entry('a', mon));
      expect((await repo.clearEntry('a', mon))?.day, mon);
      expect(await repo.entries(), isEmpty);
      final before = changes;
      expect(await repo.clearEntry('a', mon), isNull);
      expect(changes, before, reason: 'clearing nothing changes nothing');
    });

    test('a range query is inclusive at both ends and ordered by day', () async {
      for (final d in [wed, mon, fri, tue]) {
        await repo.setEntry(entry('a', d));
      }
      final got = await repo.entries(from: tue, to: fri);
      expect(got.map((e) => e.day), [tue, wed, fri]);
    });

    test('note and photo path are kept', () async {
      await repo.setEntry(Entry(
        habitId: 'a',
        day: mon,
        state: EntryState.done,
        note: 'ran 5k',
        photoPath: 'media/x.jpg',
        loggedAt: DateTime.utc(2026, 10, 5, 7),
      ));
      final e = (await repo.entries()).single;
      expect((e.note, e.photoPath), ('ran 5k', 'media/x.jpg'));
    });
  });

  group('seen days', () {
    test('marking is idempotent and reports whether anything was new', () async {
      expect(await repo.markSeen(mon), isTrue);
      expect(await repo.markSeen(mon), isFalse);
      expect(await repo.seenDays(), {mon});
    });

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
    test('round trips everything, including archived habits and seen days', () async {
      await repo.addHabit(habit('a'));
      await repo.addHabit(stayClear('s'));
      await repo.setEntry(entry('a', mon));
      await repo.setEntry(slip('s', tue));
      await repo.archive('s', wed);
      await repo.markSeen(mon);
      await repo.markSeen(tue);

      final snap = await repo.snapshot();
      expect((snap.habits.length, snap.entries.length, snap.seenDays.length), (2, 2, 2));

      final other = await openAppDatabase(factory, inMemoryDatabasePath);
      addTearDown(other.close);
      final repo2 = HabitRepository(other);
      await repo2.replaceAll(snap);
      expect(await repo2.habits(), await repo.habits());
      expect(await repo2.entries(), await repo.entries());
      expect(await repo2.seenDays(), await repo.seenDays());
    });

    test('replace discards what was there before', () async {
      await repo.addHabit(habit('old'));
      await repo.setEntry(entry('old', mon));
      await repo.markSeen(tue);
      await repo.replaceAll(Snapshot(habits: [habit('new')], entries: const [], seenDays: {wed}));
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
        await expectRefused(Snapshot(habits: [habit('a')], entries: [entry('b', mon)], seenDays: const {}));
      });

      test('two habits share an id', () async {
        await expectRefused(Snapshot(habits: [habit('a'), habit('a')], entries: const [], seenDays: const {}));
      });

      test('two entries are for the same habit and day', () async {
        await expectRefused(
            Snapshot(habits: [habit('a')], entries: [entry('a', mon), entry('a', mon, EntryState.skipped)], seenDays: const {}));
      });
    });
  });

  group('opening the database', () {
    test('removes the old app database files and starts a new empty one', () async {
      final dir = await Directory.systemTemp.createTemp('dt_db_');
      addTearDown(() => dir.delete(recursive: true));
      for (final name in ['daily_tracker.db', 'daily_tracker.db-journal', 'daily_tracker.db-wal', 'daily_tracker.db-shm']) {
        File(p.join(dir.path, name)).writeAsStringSync('old');
      }
      final db = await openAppDatabase(factory, p.join(dir.path, 'habits.db'), removeLegacyIn: dir.path);
      addTearDown(db.close);
      expect(Directory(dir.path).listSync().map((f) => p.basename(f.path)).where((n) => n.startsWith('daily_tracker')), isEmpty);
      expect(await HabitRepository(db).habits(), isEmpty);
    });

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
